--!strict
-- PlayableHoleService — Server-only singleton (Sprint 33)
-- Developer gameplay integration for the first playable one-hole test loop.
-- Coordinates VerticalSliceFlowService, ScoringService, and GameService for
-- state management; uses Roblox native physics (Part + AssemblyLinearVelocity)
-- for ball movement rather than the custom PhysicsIntegrator/BallPool chain.
--
-- Workspace lookup order (TeeSpawn / Cup):
--   1. Workspace.Courses.Hole1.TeeSpawn|Cup      (matches Rojo project hierarchy)
--   2. GameService:GetTeePosition / GetPinPosition (from CourseService metadata)
--   3. Warn + safe fallback / no-op
--
-- VSFS:SubmitSwing is called only on the FIRST shot per round because
-- GameService:OnSwingFired requires SWING state, which only exists once
-- (TEE_OFF → SWING via MarkHoleReady; SWING → BALL_IN_FLIGHT on first shot).
-- Subsequent shots apply velocity directly and track strokes locally.
-- ScoringService:CommitStroke is called via pcall after every landing —
-- it fires StrokeCommitted on GameBus so the existing HUD updates automatically.
--
-- Public API
--   StartPlayableHole(player)              → boolean
--   SpawnPlayer(player)                    → boolean
--   SpawnBall(player)                      → Part?
--   ShootBall(player, direction, power)    → boolean
--   CheckLanding(player)
--   CheckCup(player)
--   CompleteHole(player)
--   FinishRound(player)
--   ResetPlayer(player)
--   GetState(player)                       → StateSnapshot (copy)

local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")

local Logger       = require(ReplicatedStorage.Shared.Logger)
local VSFS         = require(ServerScriptService.Services.VerticalSliceFlowService)
local GameService  = require(ServerScriptService.Modules.GameService)
local ScoringService    = require(ServerScriptService.Modules.ScoringService)
local BallFlightService = require(ServerScriptService.Services.BallFlightService)
local ClubData     = require(ReplicatedStorage.Shared.Modules.ClubData)
local LieModifier  = require(ReplicatedStorage.Shared.Modules.LieModifier)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Constants ─────────────────────────────────────────────────────────────────

local CUP_RADIUS:            number = 3.0   -- studs; matches GameService HOLE_IN_RADIUS
local CUP_SINK_RADIUS:       number = 1.2   -- studs; tight cup capture during Rolling/Bouncing
local PUTTING_RADIUS:        number = 35    -- studs; within this, activate putting mode
local LAND_SPEED_THRESHOLD:  number = 0.5   -- studs/s below which ball is "settling"
local LAND_TICKS_REQUIRED:   number = 15    -- consecutive ticks below threshold to confirm landed
local DRIVER_MAX_SPEED:      number = 420   -- reference maxSpeed for per-club power scaling

-- Debug geometry positions (used when Workspace.Courses.Hole1 is absent)
local DEBUG_TEE_POS:  Vector3 = Vector3.new(0, 1,    25)   -- platform center; top surface Y=1.5
local DEBUG_BALL_POS: Vector3 = Vector3.new(0, 2,    22)   -- 0.5 studs above tee top, slightly forward
local DEBUG_CUP_POS:  Vector3 = Vector3.new(0, 0.5, -75)   -- cup marker; 100 studs from tee

-- ── Types ─────────────────────────────────────────────────────────────────────

type DevState = {
	status:    string,   -- "Idle" | "HoleReady" | "ShotInProgress" | "BallLanded" | "HoleComplete" | "RoundComplete"
	strokes:   number,
	slowTicks: number,   -- consecutive frames below LAND_SPEED_THRESHOLD
	firstShot: boolean,  -- true until first VSFS:SubmitSwing has been called
}

type StateSnapshot = {
	status:  string,
	strokes: number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean                   = false
local _balls:         { [number]: Part? }        = {}
local _states:        { [number]: DevState? }    = {}
local _heartbeatConn: RBXScriptConnection?       = nil
local _ballInFlight:  { [number]: boolean }      = {}   -- true while BallFlightService is simulating

-- ── Module ───────────────────────────────────────────────────────────────────

local PlayableHoleService = {}
PlayableHoleService.__index = PlayableHoleService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _findPlayer(userId: number): Player?
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then return p end
	end
	return nil
end

-- Returns the Hole1 folder.
-- Priority: SunnybrookMeadows.Hole1 (production) → Courses.Hole1 (debug fallback).
local function _getHole1(): Instance?
	-- SunnybrookBuilder creates Workspace.Course.Hole1 (singular "Course")
	local course = Workspace:FindFirstChild("Course")
	if course then
		local h1 = (course :: Instance):FindFirstChild("Hole1")
		if h1 then return h1 end
	end
	-- Legacy / debug fallback: Workspace.Courses.SunnybrookMeadows.Hole1
	local courses = Workspace:FindFirstChild("Courses")
	if not courses then return nil end
	local smm = (courses :: Instance):FindFirstChild("SunnybrookMeadows")
	if smm then
		local h1 = smm:FindFirstChild("Hole1")
		if h1 then return h1 end
	end
	return courses:FindFirstChild("Hole1")
end

-- Ensures a playable Hole1 exists.  Skips debug creation when the production
-- SunnybrookBuilder has already populated SunnybrookMeadows.Hole1.
local function _ensureDebugHole1(): Instance
	local course = Workspace:FindFirstChild("Course")
	if course then
		local h1 = (course :: Instance):FindFirstChild("Hole1")
		if h1 then return h1 end
	end
	local courses = Workspace:FindFirstChild("Courses")
	if courses then
		local smm = (courses :: Instance):FindFirstChild("SunnybrookMeadows")
		if smm then
			local h1 = smm:FindFirstChild("Hole1")
			if h1 then return h1 end
		end
	end

	if not courses then
		courses        = Instance.new("Folder")
		courses.Name   = "Courses"
		courses.Parent = Workspace
		warn("[PlayableHoleService] Workspace.Courses missing — auto-created for debug")
	end

	local hole1 = (courses :: Instance):FindFirstChild("Hole1")
	if hole1 then return hole1 end  -- already present; nothing to do

	warn("[PlayableHoleService] Workspace.Courses.Hole1 missing — auto-creating debug geometry")

	local newHole1   = Instance.new("Folder")
	newHole1.Name    = "Hole1"
	newHole1.Parent  = courses
	hole1            = newHole1

	-- Large floor slab so the character and ball have ground to land on
	local floor              = Instance.new("Part")
	floor.Name               = "DebugFloor"
	floor.Size               = Vector3.new(100, 1, 155)
	floor.CFrame             = CFrame.new(0, 0, -27)  -- center; top surface at Y=0.5
	floor.Anchored           = true
	floor.CanCollide         = true
	floor.BrickColor         = BrickColor.new("Medium green")
	floor.Material           = Enum.Material.Grass
	floor.CastShadow         = false
	floor.Parent             = hole1

	-- TeeSpawn — bright raised platform; SpawnPlayer pivots character above this position
	local tee                = Instance.new("Part")
	tee.Name                 = "TeeSpawn"
	tee.Size                 = Vector3.new(8, 1, 8)
	tee.CFrame               = CFrame.new(DEBUG_TEE_POS)  -- center Y=1; top at Y=1.5
	tee.Anchored             = true
	tee.CanCollide           = true
	tee.BrickColor           = BrickColor.new("Bright yellow")
	tee.Material             = Enum.Material.SmoothPlastic
	tee.CastShadow           = false
	tee.Parent               = hole1

	-- BallSpawn — invisible marker; SpawnBall places the ball here
	local ballSpawn          = Instance.new("Part")
	ballSpawn.Name           = "BallSpawn"
	ballSpawn.Size           = Vector3.new(0.4, 0.4, 0.4)
	ballSpawn.CFrame         = CFrame.new(DEBUG_BALL_POS)
	ballSpawn.Anchored       = true
	ballSpawn.CanCollide     = false
	ballSpawn.Transparency   = 1
	ballSpawn.Parent         = hole1

	-- Cup — flat neon disc (CheckCup reads its Position; visible from the tee)
	local cup                = Instance.new("Part")
	cup.Name                 = "Cup"
	cup.Shape                = Enum.PartType.Cylinder
	cup.Size                 = Vector3.new(0.5, CUP_RADIUS * 2, CUP_RADIUS * 2)
	cup.CFrame               = CFrame.new(DEBUG_CUP_POS) * CFrame.Angles(0, 0, math.pi / 2)
	cup.Anchored             = true
	cup.CanCollide           = false
	cup.BrickColor           = BrickColor.new("Bright red")
	cup.Material             = Enum.Material.Neon
	cup.Transparency         = 0.25
	cup.CastShadow           = false
	cup.Parent               = hole1

	-- Flag pole so the cup is visible from the tee (100 studs away)
	local pole               = Instance.new("Part")
	pole.Name                = "DebugFlagPole"
	pole.Size                = Vector3.new(0.2, 10, 0.2)
	pole.CFrame              = CFrame.new(DEBUG_CUP_POS + Vector3.new(0, 5, 0))
	pole.Anchored            = true
	pole.CanCollide          = false
	pole.BrickColor          = BrickColor.new("Bright yellow")
	pole.Material            = Enum.Material.SmoothPlastic
	pole.CastShadow          = false
	pole.Parent              = hole1

	print(("[PlayableHoleService] Debug Hole1 created — Tee=%s Cup=%s"):format(
		tostring(DEBUG_TEE_POS), tostring(DEBUG_CUP_POS)))

	return hole1
end

local function _getOrCreateState(player: Player): DevState
	local s = _states[player.UserId]
	if not s then
		s = { status = "Idle", strokes = 0, slowTicks = 0, firstShot = true }
		_states[player.UserId] = s
	end
	return s
end

-- Returns the Cup BasePart position from the Hole1 hierarchy, or nil if absent.
local function _getCupPosition(): Vector3?
	local hole1 = _getHole1()
	if hole1 then
		local cup = hole1:FindFirstChild("Cup")
		if cup and cup:IsA("BasePart") then
			return (cup :: BasePart).Position
		end
	end
	return nil
end

-- Returns horizontal distance from ball to cup (0 if cup not found).
local function _distanceToCup(ball: Part): number
	local cupPos = _getCupPosition()
	if not cupPos then return 0 end
	local bPos = ball.Position
	return math.floor(Vector2.new(bPos.X - cupPos.X, bPos.Z - cupPos.Z).Magnitude)
end

-- Returns a lie string for the surface immediately below ball.
-- Checks Part.Name first (SunnybrookBuilder named parts) then falls back to material.
local function _detectLie(ball: Part): string
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ball }

	local hit = Workspace:Raycast(
		ball.Position + Vector3.new(0, 0.5, 0),
		Vector3.new(0, -2, 0),
		params
	)
	if not hit then return "Fairway" end

	local mat  = hit.Material
	local inst = hit.Instance
	local name = if inst then inst.Name else ""

	if mat == Enum.Material.Sand or mat == Enum.Material.Sandstone then
		return "Bunker"
	elseif mat == Enum.Material.Water then
		return "Water"
	elseif mat == Enum.Material.SmoothPlastic then
		-- Named parts set by SunnybrookBuilder (Milestone 1.95: all playable surfaces are SmoothPlastic)
		if name == "GreenSurface" or name == "GreenFringe" then
			return "Green"
		elseif name == "TeeTurf" then
			return "Tee"
		elseif string.find(name, "Rough") then
			return "Rough"
		else
			return "Fairway"  -- FairwayStraight / FairwayCorner / FairwayDogleg
		end
	else
		-- Terrain grass or other: proximity-based Green detection
		local cupPos = _getCupPosition()
		if cupPos then
			local d2d = Vector2.new(ball.Position.X - cupPos.X, ball.Position.Z - cupPos.Z).Magnitude
			if d2d < 40 then return "Green" end
		end
		return "Fairway"
	end
end

-- Broadcasts a DevPlayState envelope so the client HUD stays in sync.
-- extra: optional table of additional payload fields (e.g. addressed, distance, lie).
local function _broadcast(userId: number, status: string, strokes: number, extra: {[string]: any}?)
	local payload: {[string]: any} = {
		userId  = userId,
		status  = status,
		strokes = strokes,
	}
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	GameBus:FireAllClients({
		eventType = "DevPlayState",
		payload   = payload :: any,
		timestamp = os.time(),
	})
end

-- Captures ball in cup during Rolling/Bouncing phase.
-- Runs sink animation, broadcasts CupIn, then schedules CompleteHole.
-- Guards against double-count via _ballInFlight mutex and status check.
local function _handleCupIn(uid: number, ball: Part)
	local p = _findPlayer(uid)
	if not p then return end
	local s = _states[uid]
	if not s then return end
	if s.status == "HoleComplete" or s.status == "RoundComplete" then return end

	BallFlightService:AbortBall(ball)
	_ballInFlight[uid]          = nil
	ball.Anchored               = true
	ball.AssemblyLinearVelocity = Vector3.zero

	s.strokes += 1
	pcall(function() ScoringService:CommitStroke(p, "cup") end)
	pcall(function() VSFS:RecordBallLanding(p, ball.CFrame.Position) end)

	local cupPos = _getCupPosition() or ball.Position
	local sinkEnd = Vector3.new(cupPos.X, cupPos.Y - 0.35, cupPos.Z)

	task.spawn(function()
		if not ball.Parent then return end
		local startPos = ball.Position
		for i = 1, 8 do
			task.wait(0.04)
			if not ball.Parent then return end
			local t     = i / 8
			local easeT = t * t
			ball.CFrame       = CFrame.new(startPos:Lerp(sinkEnd, easeT))
			ball.Transparency = math.min(easeT * 1.3, 1.0)
		end
		if ball.Parent then
			_balls[uid] = nil
			ball:Destroy()
		end
	end)

	local strokes = s.strokes
	GameBus:FireAllClients({
		eventType = "CupIn",
		payload   = { userId = uid, strokes = strokes },
		timestamp = os.time(),
	})

	task.delay(0.45, function()
		local cur = _states[uid]
		if cur and cur.status ~= "HoleComplete" and cur.status ~= "RoundComplete" then
			PlayableHoleService:CompleteHole(p)
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Kicks off the full one-hole playable flow for a player.
-- Safe even when Workspace objects or DataStore profile are absent.
function PlayableHoleService:StartPlayableHole(player: Player): boolean
	if not _initialized then
		warn("[PlayableHoleService] StartPlayableHole: not initialized")
		return false
	end

	print(("[PlayableHoleService] StartPlayableHole — %s"):format(player.Name))

	-- Reset any prior state for this player
	PlayableHoleService:ResetPlayer(player)

	-- Ensure Workspace.Courses.Hole1 exists (creates debug geometry if absent)
	_ensureDebugHole1()

	-- Start round through VSFS (requires DataStore profile — warns if unavailable)
	local startResult = VSFS:StartVerticalSlice(player)
	if not startResult.success then
		warn(("[PlayableHoleService] StartVerticalSlice failed (%s) — continuing without VSFS"):format(
			startResult.status))
	end

	-- Spawn player at tee
	local spawnedPlayer = PlayableHoleService:SpawnPlayer(player)
	if not spawnedPlayer then
		warn("[PlayableHoleService] SpawnPlayer returned false — character may not be at tee")
	end

	-- Spawn ball
	local ball = PlayableHoleService:SpawnBall(player)
	if not ball then
		warn("[PlayableHoleService] SpawnBall returned nil — no ball in world")
	end

	-- Transition pipeline to SWING (AES:Execute HoleReady)
	local holeReadyResult = VSFS:MarkHoleReady(player)
	if not holeReadyResult.success then
		Logger:Warn("PlayableHole",
			("MarkHoleReady failed (%s) — shot submission may fail"):format(holeReadyResult.status))
	end

	local s     = _getOrCreateState(player)
	s.status    = "HoleReady"
	s.strokes   = 0
	s.slowTicks = 0
	s.firstShot = true

	local dist = if ball then _distanceToCup(ball) else 0
	local lie  = if ball then _detectLie(ball) else "Tee"

	Logger:Info("PlayableHole", ("Hole Ready for %s"):format(player.Name))
	_broadcast(player.UserId, "HoleReady", 0, { distance = dist, lie = lie })
	return true
end

-- Moves the player character to the Hole1 tee position.
function PlayableHoleService:SpawnPlayer(player: Player): boolean
	if not _initialized then return false end

	local spawnPos: Vector3? = nil

	-- Primary: simple dev hierarchy
	local hole1 = _getHole1()
	if hole1 then
		local teeSpawn = hole1:FindFirstChild("TeeSpawn")
		if teeSpawn and teeSpawn:IsA("BasePart") then
			spawnPos = (teeSpawn :: BasePart).Position
		end
	end

	-- Fallback: GameService metadata (populated after StartRound)
	if not spawnPos then
		spawnPos = GameService:GetTeePosition(player)
	end

	if not spawnPos then
		warn("[PlayableHoleService] SpawnPlayer: no tee position — Workspace.Courses.Hole1.TeeSpawn missing and no active session")
		return false
	end

	local character = player.Character
	if not character then
		warn("[PlayableHoleService] SpawnPlayer: " .. player.Name .. " has no character yet")
		return false
	end

	character:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 5, 0)))
	print(("[PlayableHoleService] SpawnPlayer: %s → %s"):format(player.Name, tostring(spawnPos)))
	return true
end

-- Creates a simple white sphere ball near the tee and stores it per player.
function PlayableHoleService:SpawnBall(player: Player): Part?
	if not _initialized then return nil end

	-- Destroy existing ball first
	local existing = _balls[player.UserId]
	if existing and existing.Parent then
		existing:Destroy()
	end
	_balls[player.UserId] = nil

	-- Determine spawn position
	local ballPos: Vector3? = nil

	local hole1 = _getHole1()
	if hole1 then
		local ballSpawn = hole1:FindFirstChild("BallSpawn")
		if ballSpawn and ballSpawn:IsA("BasePart") then
			ballPos = (ballSpawn :: BasePart).Position
		else
			local teeSpawn = hole1:FindFirstChild("TeeSpawn")
			if teeSpawn and teeSpawn:IsA("BasePart") then
				ballPos = (teeSpawn :: BasePart).Position + Vector3.new(0, 1.5, 0)
			end
		end
	end

	if not ballPos then
		local teePos = GameService:GetTeePosition(player)
		if teePos then
			ballPos = teePos + Vector3.new(0, 2, 0)
		end
	end

	if not ballPos then
		warn("[PlayableHoleService] SpawnBall: no spawn position for " .. player.Name)
		return nil
	end

	local ball = Instance.new("Part")
	ball.Name         = "DevGolfBall_" .. tostring(player.UserId)
	ball.Size         = Vector3.new(0.55, 0.55, 0.55)   -- slightly larger for visibility
	ball.Shape        = Enum.PartType.Ball
	ball.Color        = Color3.fromRGB(255, 255, 255)
	ball.Material     = Enum.Material.SmoothPlastic
	ball.Reflectance  = 0.18    -- brighter gloss for in-flight visibility
	ball.Anchored     = true
	ball.CanCollide   = true
	ball.CastShadow   = true    -- soft shadow on grass
	ball.CFrame     = CFrame.new(ballPos)
	ball.Parent     = Workspace

	-- Subtle point light so the ball is visible against dark terrain or in shadow
	local ballLight      = Instance.new("PointLight")
	ballLight.Brightness = 0.7
	ballLight.Range      = 12
	ballLight.Color      = Color3.fromRGB(255, 255, 255)
	ballLight.Shadows    = false
	ballLight.Parent     = ball

	-- ── Ball-flight trail (enabled by BallFlightService on launch) ────────────────
	local trailA0        = Instance.new("Attachment")
	trailA0.Name         = "TrailAttach0"
	trailA0.Position     = Vector3.new(0, 0.21, 0)
	trailA0.Parent       = ball

	local trailA1        = Instance.new("Attachment")
	trailA1.Name         = "TrailAttach1"
	trailA1.Position     = Vector3.new(0, -0.21, 0)
	trailA1.Parent       = ball

	local trail          = Instance.new("Trail")
	trail.Name           = "BallTrail"
	trail.Attachment0    = trailA0
	trail.Attachment1    = trailA1
	trail.Lifetime       = 1.4
	trail.MinLength      = 0.05
	trail.MaxLength      = 80
	trail.Color          = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 210)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	trail.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	trail.WidthScale     = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Enabled        = false   -- BallFlightService:Launch enables this
	trail.Parent         = ball
	-- ─────────────────────────────────────────────────────────────────────────────

	_balls[player.UserId] = ball
	print(("[PlayableHoleService] SpawnBall: %s → %s"):format(player.Name, tostring(ballPos)))
	return ball
end

-- Unanchors the ball and applies a launch impulse.
-- Accepts either:
--   ShootBall(player, direction: Vector3, power: number)  — Sprint 33 compatibility
--   ShootBall(player, swingResult: {table})               — Sprint 34 SwingResult
function PlayableHoleService:ShootBall(player: Player, swingResultOrDir: any, power: number?): boolean
	if not _initialized then return false end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent then
		warn("[PlayableHoleService] ShootBall: no active ball for " .. player.Name)
		return false
	end

	local s = _states[player.UserId]
	if not s then
		warn("[PlayableHoleService] ShootBall: no state for " .. player.Name)
		return false
	end

	if s.status ~= "HoleReady" and s.status ~= "BallLanded" then
		warn(("[PlayableHoleService] ShootBall: wrong state %q for %s — ignoring"):format(
			s.status, player.Name))
		return false
	end

	local finalDir:        Vector3
	local finalPower:      number
	local _launchQuality:  string = "Good"   -- contactQuality forwarded to client FX event

	if typeof(swingResultOrDir) == "Vector3" then
		-- ── Sprint 33 path: direction + power ────────────────────────────────
		local dir: Vector3 = swingResultOrDir :: Vector3
		local pow: number  = math.max(
			if type(power) == "number" then power :: number else 60, 10)
		finalDir   = if dir.Magnitude > 0 then dir.Unit else Vector3.new(0, 0.3, -1).Unit
		finalPower = pow

	elseif type(swingResultOrDir) == "table" then
		-- ── Sprint 34 path: SwingResult table ────────────────────────────────
		local sr = swingResultOrDir :: { [string]: any }

		local launchDir: Vector3 = if typeof(sr["launchDirection"]) == "Vector3"
			then sr["launchDirection"] :: Vector3
			else Vector3.new(0, 0.2, -1).Unit
		local shotPower: number = math.max(
			if type(sr["shotPower"]) == "number" then sr["shotPower"] :: number else 60, 1)
		local cq: string  = if type(sr["contactQuality"]) == "string"
			then sr["contactQuality"] :: string else "Good"
		_launchQuality = cq
		local shape: string = if type(sr["shotShape"]) == "string"
			then sr["shotShape"] :: string else "Straight"
		local carryMult: number = if type(sr["carryMultiplier"]) == "number"
			then sr["carryMultiplier"] :: number else 1
		local sideSpin: number = if type(sr["sideSpinInput"]) == "number"
			then sr["sideSpinInput"] :: number else 0

		-- Contact quality power multipliers (must match SwingAnalyzerModule tiers)
		local powerMult: number
		if cq == "Perfect" then
			powerMult = 1.00
		elseif cq == "Good" then
			powerMult = 0.92
		elseif cq == "Thin" then
			powerMult = 0.75
		elseif cq == "Chunk" then
			powerMult = 0.45
		elseif cq == "Poor" then
			powerMult = 0.60
		else -- Mishit
			powerMult = 0.25
		end

		-- Lateral offset from shot shape
		local sideOffset: number
		if shape == "Hook" then
			sideOffset = -0.22
		elseif shape == "Draw" then
			sideOffset = -0.09
		elseif shape == "Fade" then
			sideOffset = 0.09
		elseif shape == "Slice" then
			sideOffset = 0.22
		elseif shape == "Push" then
			sideOffset = 0.10
		elseif shape == "Pull" then
			sideOffset = -0.10
		else
			sideOffset = sideSpin * 0.18
		end

		-- Right-hand perpendicular for lateral displacement
		local rightVec = launchDir:Cross(Vector3.new(0, 1, 0))
		if rightVec.Magnitude > 0.01 then
			rightVec = rightVec.Unit
		else
			rightVec = Vector3.new(1, 0, 0)
		end

		local shapeDir = launchDir + rightVec * sideOffset
		finalDir   = if shapeDir.Magnitude > 0 then shapeDir.Unit else launchDir
		finalPower = math.max(shotPower * powerMult * carryMult, 5)

		Logger:Info("PlayableHole",
			("SwingResult — contact=%s shape=%s power=%.1f"):format(cq, shape, finalPower))

	else
		warn("[PlayableHoleService] ShootBall: invalid second argument — ignoring")
		return false
	end

	-- Call SubmitSwing only on first shot (SWING state required by GameService)
	if s.firstShot then
		local aimWithArc = (finalDir + Vector3.new(0, 0.1, 0)).Unit
		pcall(function()
			VSFS:SubmitSwing(player, {
				aimVector = aimWithArc,
				power     = math.clamp(finalPower / 125, 0, 1),
			})
		end)
		s.firstShot = false
	end

	-- Extract spin data for BallFlightService (re-reads table if Sprint 34 path was taken)
	local backSpin: number  = 0.5   -- default: medium backspin
	local sideSpin: number  = 0.0   -- default: straight
	local isPutt:   boolean = false
	if type(swingResultOrDir) == "table" then
		local sr2 = swingResultOrDir :: { [string]: any }
		if type(sr2["backSpinInput"]) == "number" then
			backSpin = math.clamp(sr2["backSpinInput"] :: number, 0, 1)
		end
		if type(sr2["sideSpinInput"]) == "number" then
			sideSpin = math.clamp(sr2["sideSpinInput"] :: number, -1, 1)
		end
		isPutt = sr2["isPutt"] == true
	end

	-- ── Club + Lie effects (Milestone 2) ──────────────────────────────────────────
	-- Extract clubId sent by the client ClubManager.  Default to DRIVER / PUTTER.
	local clubId: string = if isPutt then "PUTTER" else "DRIVER"
	if type(swingResultOrDir) == "table" then
		local srC = swingResultOrDir :: { [string]: any }
		if type(srC["clubId"]) == "string" then
			clubId = srC["clubId"] :: string
		end
	end

	local clubDef = ClubData.GetClub(clubId)

	-- Base power-mult for the contact quality (mirrors the Sprint-34 block above).
	-- Used only to compute the forgiveness adjustment; no double-application.
	local QUALITY_MULT: { [string]: number } = {
		Perfect = 1.00, Good = 0.92, Thin = 0.75, Chunk = 0.45, Poor = 0.60, Mishit = 0.25,
	}
	local basePowerMult: number = QUALITY_MULT[_launchQuality] or 0.75

	if clubDef then
		-- 1. Scale power by club's maxSpeed relative to Driver.
		--    Putts are skipped: PuttingModule already applied PUTT_POWER_SCALE on the client;
		--    applying PUTTER.maxSpeed/420 (≈19%) on top would reduce distance to near-zero.
		if not isPutt then
			finalPower = finalPower * (clubDef.maxSpeed / DRIVER_MAX_SPEED)
		end

		-- 2. Forgiveness: reduce the effective power penalty on mishits.
		--    forgiveness=0.82 (CavityBack) softens a Mishit much more than forgiveness=0.35 (Blade).
		if basePowerMult < 1.0 then
			local rawPenalty   = 1.0 - basePowerMult
			local adjPenalty   = rawPenalty * (1.0 - clubDef.profile.forgiveness * 0.55)
			local adjPowerMult = 1.0 - adjPenalty
			finalPower = finalPower * (adjPowerMult / basePowerMult)
		end

		-- 3. Spin profile: Driver (spin=0.35) → low backspin; Wedges (spin=0.90) → high.
		backSpin = math.clamp(backSpin * (0.35 + clubDef.profile.spin * 0.65), 0, 1)

		-- 4. Workability: Blades (0.95) amplify shot shape; CavityBacks (0.68) dampen it.
		sideSpin = math.clamp(sideSpin * (0.50 + clubDef.profile.workability * 0.50), -1, 1)
	end

	-- Apply lie modifiers: rough / bunker reduce power, spin, and shot accuracy.
	local lieForShot: string = _detectLie(ball)
	local lieMod             = LieModifier.GetModifier(lieForShot)
	finalPower = math.max(finalPower * lieMod.power,    5)
	backSpin   = math.clamp(backSpin * lieMod.spin,     0, 1)
	sideSpin   = math.clamp(sideSpin * lieMod.accuracy, -1, 1)

	-- Lie mishit amplification: rough / bunker increase penalty for poor contact.
	-- Applied on top of club forgiveness; capped so result never hits zero.
	if lieMod.mishitScale > 1.0 and basePowerMult < 1.0 then
		local extraPenFrac = (1.0 - basePowerMult) * (lieMod.mishitScale - 1.0) * 0.55
		finalPower = finalPower * math.max(1.0 - extraPenFrac, 0.35)
	end

	-- Per-category roll friction scale: Driver rolls out; wedges stop quickly.
	-- Putts keep scale=1.0 so PuttingModule behaviour is unaffected.
	local CATEGORY_ROLL_SCALE: { [string]: number } = {
		Driver = 0.52, Wood = 0.68, Hybrid = 0.85, Iron = 1.00, Wedge = 2.10, Putter = 1.00,
	}
	local catRoll = CATEGORY_ROLL_SCALE[if clubDef then clubDef.category else "Iron"] or 1.0
	local rollFricScale: number = if isPutt
		then 1.0
		else catRoll * lieMod.rollMult

	-- Club loft; lie loftBoost adds degrees for bunker explosion feel.
	local effectiveLoft: number? = if clubDef and not isPutt
		then clubDef.loftDegrees + lieMod.loftBoost
		else nil

	-- Scale trail brightness/opacity by shot power so powerful drives feel heavier.
	-- Putts skip this because BallFlightService never enables the trail for putts.
	if not isPutt then
		local trailPart = ball:FindFirstChild("BallTrail")
		if trailPart and trailPart:IsA("Trail") then
			local p = math.clamp((finalPower - 15) / 85, 0, 1)   -- 0 at power≤15, 1 at power≥100
			;(trailPart :: Trail).LightEmission = p * 0.40        -- 0 → 0.40 glow for big shots
			;(trailPart :: Trail).Transparency  = NumberSequence.new({
				NumberSequenceKeypoint.new(0,   math.max(0, 0.10 - p * 0.08)),  -- head: more opaque on power
				NumberSequenceKeypoint.new(0.4, 0.55),
				NumberSequenceKeypoint.new(1,   1.0),
			})
		end
	end

	s.status    = "ShotInProgress"
	s.slowTicks = 0

	local uid = player.UserId
	_ballInFlight[uid] = true

	-- Shot debug summary — visible in Studio Output and live server console.
	do
		local dbgLoft  = effectiveLoft or (if isPutt then 2.0 else 10.5)
		local dbgCarry = math.round(finalPower * 3.50 * 0.72 / 3)   -- rough yards estimate
		print(string.format(
			"[ShotDebug] Club=%-14s | Lie=%-10s | Power=%5.1f | BackSpin=%.2f | Loft=%4.1f° | RollScale=%.2f | Wind=0mph | CarryEst=%3dyd",
			clubId, lieForShot, finalPower, backSpin, dbgLoft, rollFricScale, dbgCarry
		))
	end

	BallFlightService:Launch(ball, finalDir, finalPower,
		{ backSpin = backSpin, sideSpin = sideSpin, isPutt = isPutt,
		  loftDeg = effectiveLoft, rollFricScale = rollFricScale },
		{
			onStateChange = function(phase)
				local cur = _states[uid]
				if not cur then return end
				local newStatus: string
				if phase == "Bouncing" then
					newStatus = "BallBouncing"
				elseif phase == "Rolling" then
					newStatus = "BallRolling"
				else
					return
				end
				cur.status = newStatus
				_broadcast(uid, newStatus, cur.strokes)
			end,
			onStopped = function(_finalPos)
				if not _states[uid] then return end
				local p = _findPlayer(uid)
				if p then PlayableHoleService:CheckLanding(p) end
			end,
		}
	)

	-- Cup proximity monitor: captures ball during Rolling/Bouncing phases.
	-- Polls every 50 ms; exits when _ballInFlight is cleared by landing or cup capture.
	task.spawn(function()
		while _ballInFlight[uid] do
			task.wait(0.05)
			local b = _balls[uid]
			if not b or not b.Parent then break end
			local phase = BallFlightService:GetPhase(b)
			if phase == "Rolling" or phase == "Bouncing" then
				local cupPos = _getCupPosition()
				if cupPos then
					local bPos  = b.Position
					local hDist = Vector2.new(bPos.X - cupPos.X, bPos.Z - cupPos.Z).Magnitude
					local yDiff = math.abs(bPos.Y - cupPos.Y)
					if hDist <= CUP_SINK_RADIUS and yDiff < 2 then
						_handleCupIn(uid, b)
						break
					end
				end
			end
		end
	end)

	Logger:Info("PlayableHole",
		("Shot Started for %s — power=%.1f dir=%s"):format(
			player.Name, finalPower, tostring(finalDir)))
	_broadcast(player.UserId, "ShotInProgress", s.strokes)

	-- Tell client which contact quality fired so it can play the right launch FX.
	GameBus:FireAllClients({
		eventType = "ShotFired",
		payload   = { userId = player.UserId, contactQuality = _launchQuality },
		timestamp = os.time(),
	})

	return true
end

-- Called when the ball velocity has been below threshold long enough.
-- Anchors the ball, increments stroke count, updates scoring and pipeline.
function PlayableHoleService:CheckLanding(player: Player)
	if not _initialized then return end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent then return end
	if not _ballInFlight[player.UserId] then return end
	_ballInFlight[player.UserId] = nil

	local s = _states[player.UserId]
	-- Accept ShotInProgress OR the intermediate bounce/roll states that BallFlightService emits
	local inActiveShot = s and (s.status == "ShotInProgress"
		or s.status == "BallBouncing" or s.status == "BallRolling")
	if not inActiveShot then return end

	-- Settle the ball (BallFlightService already anchors it; these are idempotent guards)
	ball.Anchored               = true
	ball.AssemblyLinearVelocity = Vector3.zero

	s.strokes   += 1
	s.slowTicks  = 0
	s.status     = "BallLanded"

	-- Commit stroke through ScoringService → fires StrokeCommitted on GameBus → HUD updates
	pcall(function()
		ScoringService:CommitStroke(player, "fairway")
	end)

	-- Record landing position in pipeline (may warn on shots after first — acceptable)
	local pos = ball.CFrame.Position
	pcall(function()
		VSFS:RecordBallLanding(player, pos)
	end)

	local dist        = _distanceToCup(ball)
	local lie         = _detectLie(ball)
	local puttingMode = dist <= PUTTING_RADIUS

	Logger:Info("PlayableHole",
		("Ball Landed at %s for %s (stroke %d) — lie=%s dist=%d putt=%s"):format(
			tostring(pos), player.Name, s.strokes, lie, dist, tostring(puttingMode)))
	_broadcast(player.UserId, "BallLanded", s.strokes,
		{ distance = dist, lie = lie, puttingMode = puttingMode })

	-- Automatically check if ball is in the cup
	PlayableHoleService:CheckCup(player)
end

-- Called when the player presses E near a stopped ball.
-- Positions the character beside the ball facing the pin, then broadcasts HoleReady
-- with addressed=true so the client enables the swing engine.
function PlayableHoleService:AddressBall(player: Player): boolean
	if not _initialized then return false end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent then
		warn("[PlayableHoleService] AddressBall: no active ball for " .. player.Name)
		return false
	end

	local s = _states[player.UserId]
	if not s then return false end
	if s.status ~= "HoleReady" and s.status ~= "BallLanded" then
		warn(("[PlayableHoleService] AddressBall: wrong state %q for %s"):format(s.status, player.Name))
		return false
	end

	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end

	-- Server-side distance check to prevent trivially abusing the remote
	if ((hrp :: BasePart).Position - ball.Position).Magnitude > 15 then
		warn(("[PlayableHoleService] AddressBall: %s is too far from ball — ignoring"):format(player.Name))
		return false
	end

	-- Compute facing direction (ball → cup, clamped to horizontal)
	local ballPos   = ball.Position
	local cupPos    = _getCupPosition()
	local rawDir: Vector3 = if cupPos
		then (cupPos - ballPos)
		else Vector3.new(0, 0, -1)
	local targetDir = Vector3.new(rawDir.X, 0, rawDir.Z)
	if targetDir.Magnitude < 0.01 then
		targetDir = Vector3.new(0, 0, -1)
	else
		targetDir = targetDir.Unit
	end

	-- Stand 1.2 studs to the right of the ball-to-target line (right-handed golfer)
	local rightVec   = targetDir:Cross(Vector3.new(0, 1, 0)).Unit
	local addressPos = Vector3.new(
		ballPos.X + rightVec.X * 1.2,
		(hrp :: BasePart).Position.Y,   -- preserve current character height
		ballPos.Z + rightVec.Z * 1.2
	)

	-- Face toward the target
	local yaw    = math.atan2(-targetDir.X, -targetDir.Z)
	local charCF = CFrame.new(addressPos) * CFrame.Angles(0, yaw, 0)
	char:PivotTo(charCF)

	s.status = "HoleReady"

	local dist        = _distanceToCup(ball)
	local lie         = _detectLie(ball)
	local puttingMode = dist <= PUTTING_RADIUS

	Logger:Info("PlayableHole",
		("AddressBall: %s beside ball — lie=%s dist=%d putt=%s"):format(
			player.Name, lie, dist, tostring(puttingMode)))

	_broadcast(player.UserId, "HoleReady", s.strokes, {
		addressed   = true,
		distance    = dist,
		lie         = lie,
		puttingMode = puttingMode,
	})
	return true
end

-- Dev shortcut: teleport player 3 studs beside the ball, facing the cup.
-- Does NOT count as addressing. Player must still press E to address.
function PlayableHoleService:TeleportToBall(player: Player): boolean
	if not _initialized then return false end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent then
		print(("[PlayableHoleService] TeleportToBall: no ball for %s"):format(player.Name))
		return false
	end

	local char = player.Character
	if not char then return false end

	local ballPos = ball.CFrame.Position
	local cupPos  = _getCupPosition() or (ballPos + Vector3.new(0, 0, -5))

	-- Horizontal direction from ball toward cup
	local rawDir  = Vector3.new(cupPos.X - ballPos.X, 0, cupPos.Z - ballPos.Z)
	local faceDir = if rawDir.Magnitude > 0.01 then rawDir.Unit else Vector3.new(0, 0, -1)
	-- XZ offset: 3 studs right of the ball-to-cup line
	local rightVec     = faceDir:Cross(Vector3.new(0, 1, 0)).Unit
	local spawnXZ      = Vector3.new(
		ballPos.X + rightVec.X * 3,
		0,
		ballPos.Z + rightVec.Z * 3
	)

	-- Ground raycast from well above spawn XZ to find actual surface Y.
	-- Starting 150 studs above ball avoids missing terrain higher than ball position.
	local rcParams = RaycastParams.new()
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.FilterDescendantsInstances = { ball, char }
	local rayOrigin = Vector3.new(spawnXZ.X, ballPos.Y + 150, spawnXZ.Z)
	local groundHit = workspace:Raycast(rayOrigin, Vector3.new(0, -300, 0), rcParams)
	-- Place HumanoidRootPart 3 studs above surface (R15 hip ≈ 3 studs above feet)
	local groundY   = if groundHit then groundHit.Position.Y else ballPos.Y
	local spawnPos  = Vector3.new(spawnXZ.X, groundY + 3, spawnXZ.Z)

	local yaw = math.atan2(-(faceDir.X), -(faceDir.Z))
	char:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, yaw, 0))

	print(("[PlayableHoleService] TeleportToBall: %s → Y=%.1f (ground=%.1f)"):format(
		player.Name, spawnPos.Y, groundY))
	return true
end

-- Checks if the ball is within cup radius; if so, completes the hole.
function PlayableHoleService:CheckCup(player: Player)
	if not _initialized then return end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent then return end

	local cupPos: Vector3? = nil

	-- Primary: simple dev hierarchy
	local hole1 = _getHole1()
	if hole1 then
		local cup = hole1:FindFirstChild("Cup")
		if cup and cup:IsA("BasePart") then
			cupPos = (cup :: BasePart).Position
		end
	end

	-- Fallback: GameService pin position (from CourseService metadata)
	if not cupPos then
		cupPos = GameService:GetPinPosition(player)
	end

	if not cupPos then
		Logger:Warn("PlayableHole",
			("CheckCup: no cup position — Workspace.Courses.Hole1.Cup missing for %s"):format(player.Name))
		return
	end

	local bPos3 = ball.CFrame.Position
	local dist  = Vector2.new(bPos3.X - cupPos.X, bPos3.Z - cupPos.Z).Magnitude
	if dist <= CUP_RADIUS then
		Logger:Info("PlayableHole",
			("Cup Reached for %s (dist=%.2f studs)"):format(player.Name, dist))
		PlayableHoleService:CompleteHole(player)
	end
end

-- Marks the hole complete through VSFS and schedules round finalization.
function PlayableHoleService:CompleteHole(player: Player)
	if not _initialized then return end

	local s = _states[player.UserId]
	if not s then return end
	if s.status == "HoleComplete" or s.status == "RoundComplete" then return end

	pcall(function() VSFS:MarkHoleComplete(player) end)

	s.status = "HoleComplete"
	Logger:Info("PlayableHole", ("Hole Complete for %s"):format(player.Name))
	_broadcast(player.UserId, "HoleComplete", s.strokes)

	-- Auto-finalize after a short delay so the HUD message reads first
	task.delay(2.0, function()
		local cur = _states[player.UserId]
		if cur and cur.status == "HoleComplete" then
			PlayableHoleService:FinishRound(player)
		end
	end)
end

-- Finalizes the round through VSFS.
function PlayableHoleService:FinishRound(player: Player)
	if not _initialized then return end

	local s = _states[player.UserId]
	if not s then return end

	pcall(function() VSFS:FinalizeVerticalSlice(player) end)

	s.status = "RoundComplete"
	Logger:Info("PlayableHole", ("Round Complete for %s"):format(player.Name))
	_broadcast(player.UserId, "RoundComplete", s.strokes)
end

-- Destroys the ball, clears local state, and resets through VSFS.
function PlayableHoleService:ResetPlayer(player: Player)
	local ball = _balls[player.UserId]
	if ball and ball.Parent then
		BallFlightService:AbortBall(ball)
		ball:Destroy()
	end
	_balls[player.UserId]     = nil
	_states[player.UserId]    = nil
	_ballInFlight[player.UserId] = nil

	pcall(function() VSFS:ResetPlayer(player) end)

	Logger:Info("PlayableHole", ("Reset for %s"):format(player.Name))
	_broadcast(player.UserId, "Idle", 0)
end

-- Returns an independent copy of the player's current dev flow state.
function PlayableHoleService:GetState(player: Player): StateSnapshot
	local s = _states[player.UserId]
	if not s then
		return { status = "Idle", strokes = 0 }
	end
	return { status = s.status, strokes = s.strokes }
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PlayableHoleService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[PlayableHoleService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_balls)
	table.clear(_states)
	table.clear(_ballInFlight)

	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		PlayableHoleService:Update(dt)
	end)

	Logger:Info("PlayableHole", "ready")
	print("[PlayableHole] ready")
end

-- Landing detection is callback-driven via BallFlightService:Launch (onStopped).
-- The heartbeat connection is retained for any future per-tick server polling needs.
function PlayableHoleService:Update(_dt: number)
end

function PlayableHoleService:Destroy()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end

	for _, ball in pairs(_balls) do
		if ball and ball.Parent then
			ball:Destroy()
		end
	end
	table.clear(_balls)
	table.clear(_states)
	table.clear(_ballInFlight)

	_initialized = false
end

return PlayableHoleService
