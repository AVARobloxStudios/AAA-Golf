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
local ScoringService = require(ServerScriptService.Modules.ScoringService)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Constants ─────────────────────────────────────────────────────────────────

local CUP_RADIUS:            number = 3.0   -- studs; matches GameService HOLE_IN_RADIUS
local LAND_SPEED_THRESHOLD:  number = 0.5   -- studs/s below which ball is "settling"
local LAND_TICKS_REQUIRED:   number = 15    -- consecutive ticks below threshold to confirm landed

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

-- Returns the Hole1 folder from Workspace.Courses (Rojo hierarchy), or nil.
local function _getHole1(): Instance?
	local courses = Workspace:FindFirstChild("Courses")
	if not courses then return nil end
	return courses:FindFirstChild("Hole1")
end

-- Ensures Workspace.Courses.Hole1 exists with minimal debug geometry.
-- Creates Hole1 inside the existing Courses folder (or recreates Courses if absent)
-- so pressing F always produces a playable result even without a real course built.
local function _ensureDebugHole1(): Instance
	local courses = Workspace:FindFirstChild("Courses")
	if not courses then
		courses        = Instance.new("Folder")
		courses.Name   = "Courses"
		courses.Parent = Workspace
		warn("[PlayableHoleService] Workspace.Courses missing — auto-created for debug")
	end

	local hole1 = (courses :: Instance):FindFirstChild("Hole1")
	if hole1 then return hole1 end  -- already present; nothing to do

	warn("[PlayableHoleService] Workspace.Courses.Hole1 missing — auto-creating debug geometry")

	hole1        = Instance.new("Folder")
	(hole1 :: any).Name   = "Hole1"
	hole1.Parent = courses

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

-- Broadcasts a DevPlayState envelope so the client dev HUD stays in sync.
local function _broadcast(userId: number, status: string, strokes: number)
	GameBus:FireAllClients({
		eventType = "DevPlayState",
		payload   = {
			userId  = userId,
			status  = status,
			strokes = strokes,
		} :: any,
		timestamp = os.time(),
	})
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

	Logger:Info("PlayableHole", ("Hole Ready for %s"):format(player.Name))
	_broadcast(player.UserId, "HoleReady", 0)
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
	ball.Name       = "DevGolfBall_" .. tostring(player.UserId)
	ball.Size       = Vector3.new(0.42, 0.42, 0.42)
	ball.Shape      = Enum.PartType.Ball
	ball.BrickColor = BrickColor.new("White")
	ball.Material   = Enum.Material.SmoothPlastic
	ball.Anchored   = true
	ball.CanCollide = true
	ball.CastShadow = false
	ball.CFrame     = CFrame.new(ballPos)
	ball.Parent     = Workspace

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

	local finalDir:   Vector3
	local finalPower: number

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
		local shape: string = if type(sr["shotShape"]) == "string"
			then sr["shotShape"] :: string else "Straight"
		local carryMult: number = if type(sr["carryMultiplier"]) == "number"
			then sr["carryMultiplier"] :: number else 1
		local sideSpin: number = if type(sr["sideSpinInput"]) == "number"
			then sr["sideSpinInput"] :: number else 0

		-- Contact quality power multipliers
		local powerMult: number
		if cq == "Perfect" then
			powerMult = 1.00
		elseif cq == "Good" then
			powerMult = 0.92
		elseif cq == "Thin" then
			powerMult = 0.75
		elseif cq == "Chunk" then
			powerMult = 0.45
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

	-- Apply Roblox native physics shot
	ball.Anchored               = false
	ball.AssemblyLinearVelocity = finalDir * finalPower

	s.status    = "ShotInProgress"
	s.slowTicks = 0

	Logger:Info("PlayableHole",
		("Shot Started for %s — power=%.1f dir=%s"):format(
			player.Name, finalPower, tostring(finalDir)))
	_broadcast(player.UserId, "ShotInProgress", s.strokes)
	return true
end

-- Called when the ball velocity has been below threshold long enough.
-- Anchors the ball, increments stroke count, updates scoring and pipeline.
function PlayableHoleService:CheckLanding(player: Player)
	if not _initialized then return end

	local ball = _balls[player.UserId]
	if not ball or not ball.Parent or ball.Anchored then return end

	local s = _states[player.UserId]
	if not s or s.status ~= "ShotInProgress" then return end

	-- Settle the ball
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

	Logger:Info("PlayableHole",
		("Ball Landed at %s for %s (stroke %d)"):format(tostring(pos), player.Name, s.strokes))
	_broadcast(player.UserId, "BallLanded", s.strokes)

	-- Automatically check if ball is in the cup
	PlayableHoleService:CheckCup(player)
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

	local dist = (ball.CFrame.Position - cupPos).Magnitude
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
		ball:Destroy()
	end
	_balls[player.UserId]  = nil
	_states[player.UserId] = nil

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

	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		PlayableHoleService:Update(dt)
	end)

	Logger:Info("PlayableHole", "ready")
end

-- Polls all active in-flight balls for landing detection.
function PlayableHoleService:Update(_dt: number)
	for userId, s in pairs(_states) do
		if not s then continue end
		if s.status ~= "ShotInProgress" then continue end

		local ball = _balls[userId]
		if not ball or not ball.Parent or ball.Anchored then continue end

		local speed = ball.AssemblyLinearVelocity.Magnitude
		if speed < LAND_SPEED_THRESHOLD then
			s.slowTicks += 1
			if s.slowTicks >= LAND_TICKS_REQUIRED then
				local player = _findPlayer(userId)
				if player then
					PlayableHoleService:CheckLanding(player)
				end
			end
		else
			s.slowTicks = 0
		end
	end
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

	_initialized = false
end

return PlayableHoleService
