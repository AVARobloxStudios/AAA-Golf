--!strict
-- PlayableHoleControllerModule — Client singleton (Sprint 33 + Sprint 34, refactored Sprint 34.5)
-- Developer controls for the first playable hole.
--
-- Sprint 34.5 changes:
--   All swing orchestration moved to SwingEngineControllerModule (SECM).
--   This module is now a consumer of SECM: it provides aim direction and receives
--   SwingResult callbacks, then relays the result to the server via DeveloperAction.
--   No longer directly handles raw mouse/touch swing input or calls swing sub-modules.
--
-- Controls:
--   F            → StartPlayableHole
--   Left mouse   → Swing (handled by SwingEngineControllerModule)
--   Touch        → Same as mouse
--   Space        → Face-control timing (handled by SwingEngineControllerModule)
--   R            → Reset
--
-- Public API
--   StartPlayableHole()  — fire StartPlayableHole to server
--   Shoot()              — LEGACY: preserved for Sprint 33 test compatibility;
--                          sets lastInput, no longer fires ShootBall
--   Reset()              — fire Reset to server
--   GetState()           → ClientState (copy)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local Logger = require(ReplicatedStorage.Shared.Logger)

-- Sprint 34.5: swing orchestration delegated to SwingEngineControllerModule
local SwingEngineControllerModule = require(script.Parent.SwingEngineControllerModule)
-- Sprint 36: procedural club visual + swing animation
local GolfClubVisualModule        = require(script.Parent.GolfClubVisualModule)
-- Milestone 1: address-mode proximity prompt + proper gameplay HUD
local AddressBallModule           = require(script.Parent.AddressBallModule)
local GolfHUDModule               = require(script.Parent.GolfHUDModule)
-- Milestone 1.9: putting + hole-complete screen
local PuttingModule               = require(script.Parent.PuttingModule)
local HoleCompleteModule          = require(script.Parent.HoleCompleteModule)
-- Milestone 2: club selection + club HUD
local ClubManager                 = require(script.Parent.ClubManager)
local ClubHUDModule               = require(script.Parent.ClubHUDModule)
-- Milestone 3: direct access for SetClub / SetCarryEstimate / SetBallState
local SwingFeedbackHUDModule      = require(script.Parent.SwingFeedbackHUDModule)
-- Milestone 5: landing prediction + lie-aware dev HUD
local LieModifier                 = require(ReplicatedStorage.Shared.Modules.LieModifier)
-- Milestone 2 polish: real-time power meter reads raw swing input state
local SwingInputControllerModule  = require(script.Parent.SwingInputControllerModule)
-- Milestone 2B: centralized SFX playback (stubs are silent, no errors)
local SFXPlayer                   = require(script.Parent.SFXPlayer)

local LocalPlayer: Player = Players.LocalPlayer

local DeveloperAction: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.DeveloperAction :: RemoteEvent
local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Constants ─────────────────────────────────────────────────────────────────

local SHOT_POWER: number = 60  -- kept for GetState().power backward compatibility (Sprint 33 tests)

-- ── Types ─────────────────────────────────────────────────────────────────────

type ClientState = {
	status:       string,
	lastInput:    string,
	power:        number,
	aimDirection: Vector3,
	strokes:      number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean                = false
local _status:         string                 = "Idle"
local _lastInput:      string                 = ""
local _aimDir:         Vector3                = Vector3.new(0, 0, -1)
local _strokes:        number                 = 0
local _connections:    { RBXScriptConnection } = {}
local _devGui:         ScreenGui?             = nil
local _lblState:       TextLabel?             = nil
local _camIntroConn:   RBXScriptConnection?   = nil
local _lblBallState:   TextLabel?             = nil
local _lblFeedback:    TextLabel?             = nil   -- center-screen impact quality text
local _feedbackConn:   RBXScriptConnection?   = nil   -- fade-out animation
local _shakeConn:      RBXScriptConnection?   = nil   -- camera kick
local _firstHoleReady:    boolean                = true  -- tee intro camera fires only once
local _ballTrackerGui:    BillboardGui?          = nil   -- follows ball while in flight
local _ballCamConn:       RBXScriptConnection?   = nil   -- tracks ball during flight
local _ballCamRtnConn:    RBXScriptConnection?   = nil   -- smooth return to Follow after landing
local _introDelayPending: boolean                = false  -- guards the task.delay inside _doTeeIntroCamera
local _puttingMode:       boolean                = false  -- true when within PUTTING_RADIUS of cup
-- Milestone 5 state
local _lastLie:           string                 = "Tee"  -- lie at current ball position
local _lastDist:          number                 = 0      -- distance to pin in studs
local _landingPart:       Part?                  = nil    -- 3D landing prediction marker
local _landingLabel:      TextLabel?             = nil    -- billboard label on the marker
local _markerConn:        RBXScriptConnection?   = nil    -- RenderStepped updater for marker
-- Expanded dev HUD label refs (Milestone 5)
local _lblDevClub:  TextLabel? = nil
local _lblDevLie:   TextLabel? = nil
local _lblDevDist:  TextLabel? = nil
local _lblDevCarry: TextLabel? = nil
local _lblDevCam:   TextLabel? = nil
local _lblDevPutt:  TextLabel? = nil
-- Milestone 2 polish: swing power meter (shows during addressed state)
local _swingMeterGui:  ScreenGui?            = nil
local _swingMeterBar:  Frame?               = nil
local _swingMeterPct:  TextLabel?           = nil
local _swingMeterConn: RBXScriptConnection? = nil
local POWER_METER_MAX_PX: number            = 260   -- mirrors SwingAnalyzerModule.MAX_BACKSWING_PIXELS

local HOLE_NUM: number = 1
local HOLE_PAR: number = 4

-- ── Module ───────────────────────────────────────────────────────────────────

local PlayableHoleControllerModule = {}
PlayableHoleControllerModule.__index = PlayableHoleControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _statusToBallState(status: string): string
	if status == "HoleReady"          then return "Ready"
	elseif status == "ShotInProgress" then return "In Flight"
	elseif status == "BallBouncing"   then return "Bouncing"
	elseif status == "BallRolling"    then return "Rolling"
	elseif status == "BallLanded"     then return "Stopped"
	elseif status == "HoleComplete"
	    or status == "RoundComplete"  then return "In Cup!"
	else return "—"
	end
end

-- Finds the local player's ball in Workspace by naming convention.
local function _findBall(): Part?
	local name = "DevGolfBall_" .. tostring(LocalPlayer.UserId)
	local inst = Workspace:FindFirstChild(name)
	return if inst and inst:IsA("Part") then inst :: Part else nil
end

-- ── Ball camera helpers ───────────────────────────────────────────────────────

-- Starts a Scriptable camera that tracks the ball in flight.
-- Position glides from behind the character toward a point between character and ball,
-- rising as the ball travels further. Look direction always points at the ball.
local function _startBallCamera()
	if _ballCamConn    then _ballCamConn:Disconnect();    _ballCamConn    = nil end
	if _ballCamRtnConn then _ballCamRtnConn:Disconnect(); _ballCamRtnConn = nil end
	if _camIntroConn   then _camIntroConn:Disconnect();   _camIntroConn   = nil end
	_introDelayPending = false   -- cancel any pending intro hand-off to Follow

	local cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable

	_ballCamConn = RunService.RenderStepped:Connect(function(dt: number)
		local camInst = Workspace.CurrentCamera
		if not camInst or camInst.CameraType ~= Enum.CameraType.Scriptable then
			if _ballCamConn then _ballCamConn:Disconnect(); _ballCamConn = nil end
			return
		end
		local ball = _findBall()
		if not ball or not ball.Parent then return end

		local char = LocalPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then return end

		-- Camera glides toward a midpoint between player and ball, rising with distance.
		-- Position moves slowly (smooth glide); look direction always points at ball.
		local hrpPos    = (hrp :: BasePart).Position
		local ballPos   = ball.Position
		local horizDist = Vector3.new(ballPos.X - hrpPos.X, 0, ballPos.Z - hrpPos.Z).Magnitude
		local liftT     = math.clamp(horizDist / 160, 0, 1)   -- 0 near tee, 1 at 160+ studs
		local midPt     = hrpPos:Lerp(ballPos, 0.3 + liftT * 0.2)
		local camHeight = hrpPos.Y + 6 + liftT * 22
		local targetPos = Vector3.new(midPt.X, math.max(camHeight, ballPos.Y + 5), midPt.Z)
		local smoothPos = camInst.CFrame.Position:Lerp(targetPos, math.min(dt * 2.5, 1))
		camInst.CFrame  = CFrame.lookAt(smoothPos, ballPos + Vector3.new(0, 1, 0))
	end)
end

-- Stops the ball camera. When smooth=true, lerps camera behind the character
-- for ~1.2 s before handing off to Follow mode so the player can walk.
local function _stopBallCamera(smooth: boolean)
	if _ballCamConn    then _ballCamConn:Disconnect();    _ballCamConn    = nil end
	if _ballCamRtnConn then _ballCamRtnConn:Disconnect(); _ballCamRtnConn = nil end
	_introDelayPending = false   -- cancel any pending intro hand-off

	local cam = Workspace.CurrentCamera
	if not cam then return end

	if not smooth or cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Follow
		return
	end

	local elapsed = 0
	_ballCamRtnConn = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local camInst = Workspace.CurrentCamera
		local char    = LocalPlayer.Character
		local hrp     = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp or not camInst or camInst.CameraType ~= Enum.CameraType.Scriptable then
			if _ballCamRtnConn then _ballCamRtnConn:Disconnect(); _ballCamRtnConn = nil end
			return
		end
		local hrpCF    = (hrp :: BasePart).CFrame
		local behind   = (hrpCF * CFrame.new(0, 5, 12)).Position
		local lookAt   = (hrp :: BasePart).Position + Vector3.new(0, 2, 0)
		local targetCF = CFrame.lookAt(behind, lookAt)
		camInst.CFrame = camInst.CFrame:Lerp(targetCF, math.min(dt * 4, 1))
		if elapsed >= 1.2 then
			if _ballCamRtnConn then _ballCamRtnConn:Disconnect(); _ballCamRtnConn = nil end
			camInst.CameraType = Enum.CameraType.Follow
		end
	end)
end

-- ── Ball tracker helpers ──────────────────────────────────────────────────────

-- Attaches a yellow dot BillboardGui to the ball so it remains visible during
-- flight. AlwaysOnTop ensures it shows even when ball is behind terrain.
local function _createBallTracker(ball: Part): BillboardGui
	local bg             = Instance.new("BillboardGui")
	bg.Name              = "BallTracker"
	bg.Size              = UDim2.new(0, 40, 0, 40)
	bg.StudsOffset       = Vector3.new(0, 3.5, 0)
	bg.AlwaysOnTop       = true
	bg.ResetOnSpawn      = false

	local dot                    = Instance.new("Frame")
	dot.BackgroundColor3         = Color3.fromRGB(255, 210, 0)
	dot.BorderSizePixel          = 0
	dot.Size                     = UDim2.new(1, 0, 1, 0)
	dot.Parent                   = bg

	local corner              = Instance.new("UICorner")
	corner.CornerRadius       = UDim.new(1, 0)
	corner.Parent             = dot

	local stroke                 = Instance.new("UIStroke")
	stroke.Color                 = Color3.fromRGB(220, 80, 0)
	stroke.Thickness             = 2.5
	stroke.Parent                = dot

	bg.Parent = ball
	return bg
end

local function _destroyBallTracker()
	if _ballTrackerGui and _ballTrackerGui.Parent then
		_ballTrackerGui:Destroy()
	end
	_ballTrackerGui = nil
end

-- ── Impact Polish helpers ─────────────────────────────────────────────────────

-- Shows centre-screen impact-quality text that fades out after ~1.5 s.
local function _showFeedback(text: string, color: Color3)
	if not _lblFeedback then return end
	_lblFeedback.Text      = text
	_lblFeedback.TextColor3 = color
	if _feedbackConn then _feedbackConn:Disconnect() end
	local elapsed = 0
	local HOLD    = 0.75   -- seconds fully visible
	local FADE    = 0.65   -- seconds to fade to invisible
	_feedbackConn = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local lbl = _lblFeedback
		if not lbl then
			if _feedbackConn then _feedbackConn:Disconnect(); _feedbackConn = nil end
			return
		end
		local alpha: number
		if elapsed < HOLD then
			alpha = 0
		else
			alpha = math.min((elapsed - HOLD) / FADE, 1.0)
		end
		lbl.TextTransparency = alpha
		if alpha >= 1.0 then
			if _feedbackConn then _feedbackConn:Disconnect(); _feedbackConn = nil end
		end
	end)
end

-- FOV-pulse camera kick scaled by contact quality and shot power.
-- Perfect + full power → ~7° punch; Mishit → ~1°. Total duration ~0.22 s.
local function _cameraKick(quality: string?, power01: number?)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	if _shakeConn then _shakeConn:Disconnect() end
	local baseFov = cam.FieldOfView

	local qualScale: number
	if quality == "Perfect" then qualScale = 1.4
	elseif quality == "Good" then qualScale = 1.0
	elseif quality == "Thin" then qualScale = 0.55
	elseif quality == "Chunk" or quality == "Poor" then qualScale = 0.35
	else qualScale = 0.15  -- Mishit: barely perceptible
	end
	local p01      = math.clamp(if type(power01) == "number" then power01 :: number else 0.8, 0.2, 1.0)
	local fovDelta = 5 * qualScale * p01   -- max ~7° for Perfect+full-power

	local elapsed  = 0
	_shakeConn = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local t = math.min(elapsed / 0.22, 1.0)
		local pulse: number = if t < 0.22
			then math.exp(-t * 12) * math.sin(t * math.pi * 3.5)
			else 0
		cam.FieldOfView = baseFov - pulse * fovDelta
		if t >= 1.0 then
			cam.FieldOfView = baseFov
			if _shakeConn then _shakeConn:Disconnect(); _shakeConn = nil end
		end
	end)
end

-- Client-side launch particles at ball position, varied by contact quality.
local function _spawnLaunchFX(quality: string)
	local ballName = "DevGolfBall_" .. tostring(LocalPlayer.UserId)
	local ballInst = Workspace:FindFirstChild(ballName)
	if not ballInst or not ballInst:IsA("Part") then return end
	local ballPart = ballInst :: Part

	local function makeEmitter(count: number): ParticleEmitter
		local e       = Instance.new("ParticleEmitter")
		e.Rate        = 0
		e.RotSpeed    = NumberRange.new(-45, 45)
		e.Rotation    = NumberRange.new(0, 360)
		e.Parent      = ballPart
		e:Emit(count)
		Debris:AddItem(e, 2)
		return e
	end

	if quality == "Perfect" then
		-- Grass puff (bigger than Good)
		local g          = makeEmitter(0)
		g.Speed          = NumberRange.new(10, 28)
		g.Lifetime       = NumberRange.new(0.28, 0.60)
		g.Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0) })
		g.Color          = ColorSequence.new(Color3.fromRGB(130, 210, 90))
		g.LightEmission  = 0.15
		g:Emit(22)
		-- Bright spark burst
		local sp         = Instance.new("ParticleEmitter")
		sp.Rate          = 0
		sp.Speed         = NumberRange.new(22, 55)
		sp.Lifetime      = NumberRange.new(0.08, 0.22)
		sp.Size          = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
		sp.Color         = ColorSequence.new(Color3.fromRGB(255, 255, 210))
		sp.LightEmission = 1.0
		sp.Parent        = ballPart
		sp:Emit(18)
		Debris:AddItem(sp, 1)
		-- Brief PointLight flash for impact "pop" on Perfect shots
		local flash         = Instance.new("PointLight")
		flash.Brightness    = 8
		flash.Range         = 18
		flash.Color         = Color3.fromRGB(255, 240, 180)
		flash.Shadows       = false
		flash.Parent        = ballPart
		Debris:AddItem(flash, 0.14)

	elseif quality == "Good" then
		-- Grass puff, smaller
		local g          = makeEmitter(0)
		g.Speed          = NumberRange.new(5, 15)
		g.Lifetime       = NumberRange.new(0.20, 0.45)
		g.Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		g.Color          = ColorSequence.new(Color3.fromRGB(140, 200, 100))
		g.LightEmission  = 0.05
		g:Emit(10)

	elseif quality == "Thin" then
		-- Metallic spark (top-of-ball thin contact)
		local sp         = makeEmitter(0)
		sp.Speed         = NumberRange.new(12, 30)
		sp.Lifetime      = NumberRange.new(0.08, 0.18)
		sp.Size          = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0) })
		sp.Color         = ColorSequence.new(Color3.fromRGB(220, 230, 255))
		sp.LightEmission = 0.75
		sp:Emit(9)

	elseif quality == "Chunk" or quality == "Poor" then
		-- Dirt clod puff
		local d          = makeEmitter(0)
		d.Speed          = NumberRange.new(3, 11)
		d.Lifetime       = NumberRange.new(0.30, 0.65)
		d.Size           = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.50),
			NumberSequenceKeypoint.new(0.4, 0.38),
			NumberSequenceKeypoint.new(1, 0),
		})
		d.Color          = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(95, 65, 38)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 115, 80)),
		})
		d.LightEmission  = 0
		d:Emit(if quality == "Chunk" then 22 else 14)

	else -- Mishit
		-- Large dirt eruption
		local d          = makeEmitter(0)
		d.Speed          = NumberRange.new(2, 9)
		d.Lifetime       = NumberRange.new(0.40, 0.85)
		d.Size           = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(0.3, 0.50),
			NumberSequenceKeypoint.new(1, 0),
		})
		d.Color          = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 58, 32)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 100, 68)),
		})
		d.LightEmission  = 0
		d:Emit(30)
	end
end

-- ── Dev HUD helpers ───────────────────────────────────────────────────────────

local function _updateDevHUD()
	if _lblState then
		_lblState.Text = ("State: %s  |  %d stroke%s"):format(_status, _strokes, if _strokes == 1 then "" else "s")
	end
	if _lblBallState then
		_lblBallState.Text = "Ball: " .. _statusToBallState(_status)
	end
	-- Club row: name + lock indicator
	if _lblDevClub then
		local def    = ClubManager:GetCurrentClub()
		local name   = if def then def.displayName else ClubManager:GetCurrentClubId()
		local suffix = if ClubManager:IsLocked() then "  [locked]" else ""
		_lblDevClub.Text = "Club: " .. name .. suffix
	end
	-- Lie
	if _lblDevLie  then _lblDevLie.Text  = "Lie: "  .. _lastLie end
	-- Distance to pin
	if _lblDevDist then
		if _lastDist <= 0 then
			_lblDevDist.Text = "Dist: —"
		elseif _lastDist < 30 then
			_lblDevDist.Text = ("Dist: %d ft"):format(math.round(_lastDist * 3))
		else
			_lblDevDist.Text = ("Dist: %d yd"):format(math.round(_lastDist))
		end
	end
	-- Carry estimate: club maxRange × lie.power × 0.80 (empirical accuracy factor)
	if _lblDevCarry then
		local def    = ClubManager:GetCurrentClub()
		local lieMod = LieModifier.GetModifier(_lastLie)
		if def and def.maxRangeYards then
			_lblDevCarry.Text = ("Carry: ~%d yd"):format(math.round(def.maxRangeYards * lieMod.power * 0.80))
		else
			_lblDevCarry.Text = "Carry: —"
		end
	end
	-- Camera mode
	if _lblDevCam then
		local cam     = Workspace.CurrentCamera
		local camType = if cam then tostring(cam.CameraType):gsub("Enum%.CameraType%.", "") else "—"
		_lblDevCam.Text = "Cam: " .. camType
	end
	-- Putting mode
	if _lblDevPutt then
		_lblDevPutt.Text = "Putting: " .. (if _puttingMode then "Yes" else "No")
	end
end

-- Immediately push the current ClubManager selection to HUD, visual, and dev HUD.
-- Called directly from Z/X InputBegan so the update is synchronous (not deferred via
-- task.spawn like OnChanged callbacks).
local function _syncSelectedClub()
	local clubId  = ClubManager:GetCurrentClubId()
	local clubDef = ClubManager:GetCurrentClub()
	if clubDef then
		ClubHUDModule:SetClub(clubDef)
		GolfClubVisualModule:SetClub(clubDef.category)
	end
	_updateDevHUD()
	print("[ClubPipeline] synced clubId=" .. clubId)
end

local function _buildDevHUD()
	local playerGui: PlayerGui = LocalPlayer.PlayerGui
	if _devGui and _devGui.Parent then _devGui:Destroy() end

	local screenGui               = Instance.new("ScreenGui")
	screenGui.Name                = "DevPlayHUD"
	screenGui.ResetOnSpawn        = false
	screenGui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder        = 99

	-- Top-left panel with all gameplay debug info (Milestone 5)
	local frame                   = Instance.new("Frame")
	frame.BackgroundColor3        = Color3.fromRGB(10, 10, 10)
	frame.BackgroundTransparency  = 0.35
	frame.Size                    = UDim2.new(0, 238, 0, 248)
	frame.Position                = UDim2.new(0, 10, 0, 10)
	frame.AnchorPoint             = Vector2.new(0, 0)
	frame.BorderSizePixel         = 0
	frame.Parent                  = screenGui

	local ROW_H = 20
	local function makeRow(text: string, y: number, bold: boolean, color: Color3): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size                   = UDim2.new(1, -14, 0, ROW_H)
		lbl.Position               = UDim2.new(0, 7, 0, y)
		lbl.Font                   = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		lbl.TextSize               = if bold then 13 else 12
		lbl.TextColor3             = color
		lbl.TextXAlignment         = Enum.TextXAlignment.Left
		lbl.TextTruncate           = Enum.TextTruncate.AtEnd
		lbl.Text                   = text
		lbl.Parent                 = frame
		return lbl
	end

	local W     = Color3.fromRGB(210, 210, 210)
	local G     = Color3.fromRGB(120, 220, 120)
	local DIM   = Color3.fromRGB(130, 130, 140)
	local GOLD  = Color3.fromRGB(255, 200, 50)
	local CYAN  = Color3.fromRGB(130, 210, 255)
	local ORG   = Color3.fromRGB(255, 185, 80)

	makeRow("[ GOLF DEBUG ]",      6,   true,  GOLD)
	_lblDevClub  = makeRow("Club: —",           28,  false, CYAN)
	_lblDevLie   = makeRow("Lie: —",            50,  false, W)
	_lblDevDist  = makeRow("Dist: —",           72,  false, W)
	_lblDevCarry = makeRow("Carry: —",          94,  false, ORG)
	makeRow("Wind: 0 mph",        116, false, DIM)   -- static; wind system = placeholder
	_lblBallState= makeRow("Ball: —",           138, false, G)
	_lblDevCam   = makeRow("Cam: Follow",       160, false, DIM)
	_lblDevPutt  = makeRow("Putting: No",       182, false, W)
	_lblState    = makeRow("State: Idle | 0",   204, false, DIM)
	makeRow("Z/X=Club  E=Addr  F=Start  R=Reset  V=DevHUD", 226, false, Color3.fromRGB(100, 100, 110))

	-- Impact quality feedback — centre-screen, invisible until shot fires
	local feedLbl                    = Instance.new("TextLabel")
	feedLbl.BackgroundTransparency   = 1
	feedLbl.Size                     = UDim2.new(0, 360, 0, 56)
	feedLbl.Position                 = UDim2.new(0.5, -180, 0.28, 0)
	feedLbl.Font                     = Enum.Font.GothamBold
	feedLbl.TextSize                 = 30
	feedLbl.TextXAlignment           = Enum.TextXAlignment.Center
	feedLbl.TextStrokeTransparency   = 0.45
	feedLbl.TextStrokeColor3         = Color3.fromRGB(0, 0, 0)
	feedLbl.TextTransparency         = 1
	feedLbl.Text                     = ""
	feedLbl.Parent                   = screenGui
	_lblFeedback = feedLbl

	screenGui.Parent = LocalPlayer.PlayerGui
	_devGui = screenGui
end

-- ── Impact / landing VFX ──────────────────────────────────────────────────────
-- Brief dirt-and-grass particle burst spawned at the ball position on impact.
-- On landing, a smaller dust puff marks where the ball first touches down.
-- Parts are invisible anchors; Debris cleans them up after the emitter expires.

local function _spawnImpactVFX(position: Vector3)
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Size         = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame       = CFrame.new(position)
	part.Parent       = Workspace

	local emitter               = Instance.new("ParticleEmitter")
	emitter.Color               = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(118, 93, 40)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(88, 148, 50)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(155, 130, 75)),
	})
	emitter.Transparency        = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.05),
		NumberSequenceKeypoint.new(0.55, 0.40),
		NumberSequenceKeypoint.new(1,    1.00),
	})
	emitter.LightEmission       = 0.08
	emitter.Size                = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	emitter.SpreadAngle         = Vector2.new(55, 55)
	emitter.Speed               = NumberRange.new(7, 18)
	emitter.Lifetime            = NumberRange.new(0.30, 0.55)
	emitter.Rate                = 0
	emitter.Rotation            = NumberRange.new(0, 360)
	emitter.RotSpeed            = NumberRange.new(-30, 30)
	emitter.Parent              = part
	emitter:Emit(12)

	Debris:AddItem(part, 1.2)
end

local function _spawnLandingVFX(position: Vector3)
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Size         = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame       = CFrame.new(position)
	part.Parent       = Workspace

	local emitter               = Instance.new("ParticleEmitter")
	emitter.Color               = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 82, 38)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(138, 115, 70)),
	})
	emitter.Transparency        = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.10),
		NumberSequenceKeypoint.new(1, 1.00),
	})
	emitter.Size                = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.20),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	emitter.SpreadAngle         = Vector2.new(35, 35)
	emitter.Speed               = NumberRange.new(4, 10)
	emitter.Lifetime            = NumberRange.new(0.20, 0.40)
	emitter.Rate                = 0
	emitter.Parent              = part
	emitter:Emit(6)

	Debris:AddItem(part, 0.8)
end

-- ── Swing power meter ─────────────────────────────────────────────────────────
-- Appears bottom-center while the player is addressed (before the swing fires).
-- Bar fills green→yellow→red as backswing drag increases.

local function _hideSwingMeter()
	if _swingMeterConn then _swingMeterConn:Disconnect(); _swingMeterConn = nil end
	if _swingMeterGui and _swingMeterGui.Parent then _swingMeterGui:Destroy() end
	_swingMeterGui  = nil
	_swingMeterBar  = nil
	_swingMeterPct  = nil
end

local function _showSwingMeter()
	_hideSwingMeter()

	local sg          = Instance.new("ScreenGui")
	sg.Name           = "SwingPowerMeter"
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 101
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent         = LocalPlayer.PlayerGui
	_swingMeterGui    = sg

	-- Power % label just above the bar
	local pctLbl                   = Instance.new("TextLabel")
	pctLbl.BackgroundTransparency  = 1
	pctLbl.Size                    = UDim2.new(0, 200, 0, 28)
	pctLbl.Position                = UDim2.new(0.5, -100, 1, -112)
	pctLbl.AnchorPoint             = Vector2.new(0, 1)
	pctLbl.Font                    = Enum.Font.GothamBold
	pctLbl.TextSize                = 18
	pctLbl.TextColor3              = Color3.fromRGB(255, 255, 255)
	pctLbl.TextXAlignment          = Enum.TextXAlignment.Center
	pctLbl.TextStrokeTransparency  = 0.40
	pctLbl.TextStrokeColor3        = Color3.fromRGB(0, 0, 0)
	pctLbl.Text                    = "0%"
	pctLbl.Parent                  = sg
	_swingMeterPct = pctLbl

	-- Background bar track
	local bg              = Instance.new("Frame")
	bg.Size               = UDim2.new(0, 280, 0, 16)
	bg.Position           = UDim2.new(0.5, -140, 1, -82)
	bg.AnchorPoint        = Vector2.new(0, 1)
	bg.BackgroundColor3   = Color3.fromRGB(25, 25, 35)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel    = 0
	bg.Parent             = sg
	local bgc             = Instance.new("UICorner")
	bgc.CornerRadius      = UDim.new(0, 6)
	bgc.Parent            = bg

	-- Fill bar (starts at zero width)
	local fill            = Instance.new("Frame")
	fill.Size             = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 210, 90)
	fill.BorderSizePixel  = 0
	fill.Parent           = bg
	local fc              = Instance.new("UICorner")
	fc.CornerRadius       = UDim.new(0, 6)
	fc.Parent             = fill
	_swingMeterBar = fill

	-- "POWER" label below the bar
	local captionLbl                   = Instance.new("TextLabel")
	captionLbl.BackgroundTransparency  = 1
	captionLbl.Size                    = UDim2.new(0, 200, 0, 18)
	captionLbl.Position                = UDim2.new(0.5, -100, 1, -66)
	captionLbl.AnchorPoint             = Vector2.new(0, 1)
	captionLbl.Font                    = Enum.Font.Gotham
	captionLbl.TextSize                = 11
	captionLbl.TextColor3              = Color3.fromRGB(180, 180, 190)
	captionLbl.TextXAlignment          = Enum.TextXAlignment.Center
	captionLbl.Text                    = "POWER  ·  Drag down ↓  Release ↑"
	captionLbl.Parent                  = sg

	_swingMeterConn = RunService.RenderStepped:Connect(function()
		local bar = _swingMeterBar
		local pct = _swingMeterPct
		if not bar or not pct then return end

		local state   = SwingInputControllerModule:GetSwingState()
		local phase   = state.phase
		local power01 = 0.0

		if phase == "Backswing" then
			local delta = state.currentPosition.Y - state.startPosition.Y
			power01 = math.clamp(delta / POWER_METER_MAX_PX, 0, 1)
		elseif phase == "Downswing" or phase == "Released" then
			power01 = math.clamp(state.maxBackswingDistance / POWER_METER_MAX_PX, 0, 1)
		end

		bar.Size = UDim2.new(power01, 0, 1, 0)
		pct.Text = math.round(power01 * 100) .. "%"

		-- Color gradient: green (0%) → yellow (55%) → red (100%)
		local r: number = math.round(math.min(1, power01 * 2)    * 230)
		local g: number = math.round(math.min(1, 2 - power01 * 2) * 200)
		bar.BackgroundColor3 = Color3.fromRGB(r, g, 40)
	end)
end

-- ── Landing prediction marker ─────────────────────────────────────────────────
-- Shown while the player is in addressed (pre-swing) state.
-- A flat 5×5 disc on the ground at the estimated carry point, with a carry label.

local function _hideLandingMarker()
	if _markerConn then _markerConn:Disconnect(); _markerConn = nil end
	if _landingPart and _landingPart.Parent then _landingPart:Destroy() end
	_landingPart  = nil
	_landingLabel = nil
end

local function _showLandingMarker()
	_hideLandingMarker()
	local ball = _findBall()
	if not ball then return end

	local marker           = Instance.new("Part")
	marker.Name            = "LandingPrediction"
	marker.Anchored        = true
	marker.CanCollide      = false
	marker.CastShadow      = false
	marker.Material        = Enum.Material.Neon
	marker.Color           = Color3.fromRGB(255, 210, 55)
	marker.Transparency    = 0.44
	marker.Size            = Vector3.new(5, 0.14, 5)
	marker.Parent          = workspace
	_landingPart = marker

	local bg           = Instance.new("BillboardGui")
	bg.Size            = UDim2.new(0, 120, 0, 28)
	bg.StudsOffset     = Vector3.new(0, 1.8, 0)
	bg.AlwaysOnTop     = false
	bg.MaxDistance     = 600
	bg.Parent          = marker

	local lbl                   = Instance.new("TextLabel")
	lbl.BackgroundColor3        = Color3.fromRGB(0, 0, 0)
	lbl.BackgroundTransparency  = 0.30
	lbl.Size                    = UDim2.new(1, 0, 1, 0)
	lbl.Font                    = Enum.Font.GothamBold
	lbl.TextSize                = 12
	lbl.TextColor3              = Color3.fromRGB(255, 230, 100)
	lbl.TextXAlignment          = Enum.TextXAlignment.Center
	lbl.Text                    = "— yd"
	lbl.Parent                  = bg
	_landingLabel = lbl

	local rcParams = RaycastParams.new()
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.FilterDescendantsInstances = { ball, marker }

	_markerConn = RunService.RenderStepped:Connect(function()
		local p = _landingPart
		if not p or not p.Parent then
			if _markerConn then _markerConn:Disconnect(); _markerConn = nil end
			return
		end
		local b = _findBall()
		if not b or not b.Parent then return end

		local cam = Workspace.CurrentCamera
		if not cam then return end

		local look   = cam.CFrame.LookVector
		local aimDir = Vector3.new(look.X, 0, look.Z)
		if aimDir.Magnitude < 0.01 then return end
		aimDir = aimDir.Unit

		local def    = ClubManager:GetCurrentClub()
		local lieMod = LieModifier.GetModifier(_lastLie)
		local mr: number = 80
		if def then
			local raw = def.maxRangeYards
			if raw then mr = raw end
		end
		local carryEst = math.round(mr * lieMod.power * 0.80)

		local ballPos = b.Position
		local predX   = ballPos.X + aimDir.X * carryEst
		local predZ   = ballPos.Z + aimDir.Z * carryEst

		local hit = workspace:Raycast(
			Vector3.new(predX, ballPos.Y + 80, predZ),
			Vector3.new(0, -160, 0),
			rcParams
		)
		local groundY = if hit then hit.Position.Y else ballPos.Y

		p.CFrame = CFrame.new(predX, groundY + 0.08, predZ)

		local ll = _landingLabel
		if ll then ll.Text = carryEst .. " yd carry" end
	end)
end

-- ── Camera intro ─────────────────────────────────────────────────────────────

-- Smoothly transitions the camera to a cinematic tee view (behind tee, looking
-- at the green) for ~1.8 s, then hands control back to Follow mode.
-- Uses fixed world-space targets so it works even before the character settles.
local function _doTeeIntroCamera()
	-- Cancel any in-progress intro
	if _camIntroConn then
		_camIntroConn:Disconnect()
		_camIntroConn = nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- Target: behind and above the tee, looking toward the green flag
	local behindTee = Vector3.new(-8, 14, 212)
	local greenPos  = Vector3.new(88, 3, -145)
	local startCF   = camera.CFrame
	local targetCF  = CFrame.lookAt(behindTee, greenPos)

	camera.CameraType = Enum.CameraType.Scriptable

	local elapsed  = 0
	local duration = 1.8
	_camIntroConn  = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1.0)
		alpha = 1 - (1 - alpha) ^ 3   -- ease-out cubic
		camera.CFrame = startCF:Lerp(targetCF, alpha)
		if alpha >= 1.0 then
			if _camIntroConn then
				_camIntroConn:Disconnect()
				_camIntroConn = nil
			end
			-- Hold 2 s then hand back to Follow. _introDelayPending guards against
			-- this firing if a swing has already started the ball camera.
			_introDelayPending = true
			task.delay(2.0, function()
				if not _introDelayPending then return end
				_introDelayPending = false
				local cam = Workspace.CurrentCamera
				if cam and cam.CameraType == Enum.CameraType.Scriptable then
					cam.CameraType = Enum.CameraType.Follow
				end
			end)
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PlayableHoleControllerModule:StartPlayableHole()
	if not _initialized then
		warn("[PlayableHole] StartPlayableHole: not initialized — was Init() called?")
		return
	end
	print("[PlayableHole] F pressed — StartPlayableHole")
	_status    = "Starting…"
	_strokes   = 0
	_lastInput = "StartPlayableHole"
	_updateDevHUD()
	-- SwingEngine not started here; it starts only after the player addresses the ball
	local ok, err = pcall(function()
		DeveloperAction:FireServer({ action = "StartPlayableHole" })
	end)
	if not ok then
		warn("[PlayableHole] DeveloperAction:FireServer failed: " .. tostring(err))
	else
		print("[PlayableHole] StartPlayableHole fired to server")
	end
end

-- LEGACY: preserved for Sprint 33 test backward compatibility.
-- Shoot() no longer fires ShootBall to the server; drag-to-swing is the real path.
function PlayableHoleControllerModule:Shoot()
	if not _initialized then return end
	local camera   = Workspace.CurrentCamera
	local baseLook = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	_aimDir    = (baseLook + Vector3.new(0, 0.25, 0)).Unit
	_lastInput = "Shoot"
	_updateDevHUD()
	-- Sprint 34: Space is face-control timing; primary swing is mouse/touch drag.
end

function PlayableHoleControllerModule:Reset()
	if not _initialized then return end
	_status         = "Idle"
	_strokes        = 0
	_lastInput      = "Reset"
	_firstHoleReady = true
	_updateDevHUD()
	_destroyBallTracker()
	_stopBallCamera(false)
	SwingEngineControllerModule:Stop()
	SwingEngineControllerModule:Reset()
	GolfClubVisualModule:Detach()
	AddressBallModule:Disable()
	PuttingModule:Deactivate()
	HoleCompleteModule:Hide()
	GolfHUDModule:SetPuttingMode(false)
	_puttingMode = false
	GolfHUDModule:SetStrokes(0)
	GolfHUDModule:SetBallState("—")
	GolfHUDModule:SetDistance(0)
	GolfHUDModule:SetLie("—")
	_hideLandingMarker()
	_hideSwingMeter()
	_lastLie  = "Tee"
	_lastDist = 0
	ClubManager:SetLocked(false)
	ClubManager:SetClub("DRIVER")
	ClubHUDModule:SetDistance(0)
	ClubHUDModule:SetLie("—")
	pcall(function()
		DeveloperAction:FireServer({ action = "Reset" })
	end)
	Logger:Info("PlayableHole", "Reset fired to server")
end

function PlayableHoleControllerModule:GetState(): ClientState
	return {
		status       = _status,
		lastInput    = _lastInput,
		power        = SHOT_POWER,
		aimDirection = _aimDir,
		strokes      = _strokes,
	}
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PlayableHoleControllerModule:Init()
	if _initialized then
		warn("[PlayableHoleControllerModule] Init called twice — skipping")
		return
	end
	_initialized    = true
	_status         = "Idle"
	_strokes        = 0
	_lastInput      = ""
	_aimDir         = Vector3.new(0, 0, -1)
	_firstHoleReady = true

	-- ── Golf HUD (production gameplay) ───────────────────────────────────────
	GolfHUDModule:Init()
	GolfHUDModule:SetHole(1, 4)

	-- ── Club system ───────────────────────────────────────────────────────────
	ClubManager:Init()
	ClubHUDModule:Init()
	local initClub = ClubManager:GetCurrentClub()
	if initClub then ClubHUDModule:SetClub(initClub) end
	ClubManager:OnChanged(function()
		_syncSelectedClub()
	end)

	-- ── Club visual ──────────────────────────────────────────────────────────
	GolfClubVisualModule:Init()
	-- Sync visual module to initial club category (defaults to Driver on fresh load)
	if initClub then GolfClubVisualModule:SetClub(initClub.category) end

	local clubUpdateConn = RunService.RenderStepped:Connect(function(dt: number)
		GolfClubVisualModule:Update(dt)
	end)
	table.insert(_connections, clubUpdateConn)

	-- ── SwingEngine setup ─────────────────────────────────────────────────────
	SwingEngineControllerModule:Init()

	SwingEngineControllerModule:SetAimDirectionProvider(function(): Vector3
		local camera = Workspace.CurrentCamera
		return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	end)

	SwingEngineControllerModule:SetSwingResultCallback(function(swingResult: any)
		-- Gate: only send to server in shootable states
		if _status ~= "HoleReady" and _status ~= "BallLanded" then return end
		-- Apply putting modifications if active (flattens launch, reduces power)
		local finalResult = PuttingModule:ModifySwingResult(swingResult)
		_aimDir    = finalResult.launchDirection
		_lastInput = "Swing"
		_hideLandingMarker()   -- remove prediction disc the moment the ball launches
		_hideSwingMeter()      -- remove power bar immediately on swing release
		-- Impact VFX: brief grass/dirt burst at ball contact point
		local impactBall = _findBall()
		if impactBall then
			_spawnImpactVFX(impactBall.Position)
		end
		-- Impact sound (stubs are silent; real IDs come from SoundConfig)
		local impactClub = ClubManager:GetCurrentClub()
		if impactClub then
			SFXPlayer:PlayImpact(impactClub.category)
		end
		_updateDevHUD()

		-- Camera kick: scale by quality and power for satisfying feel feedback
		local cq    = tostring(finalResult.contactQuality)
		local p01   = if type((swingResult :: { [string]: any })["power01"]) == "number"
			then (swingResult :: { [string]: any })["power01"] :: number else 0.8
		_cameraKick(cq, p01)

		-- Update debug HUD: club name + carry estimate (immediately, no server round-trip)
		local dbgClubDef = ClubManager:GetCurrentClub()
		if dbgClubDef then
			SwingFeedbackHUDModule:SetClub(tostring(dbgClubDef.displayName))
			local maxRange = dbgClubDef.maxRangeYards
			if type(maxRange) == "number" then
				local cqMult: number = if type((swingResult :: { [string]: any })["carryMultiplier"]) == "number"
					then (swingResult :: { [string]: any })["carryMultiplier"] :: number else 0.9
				SwingFeedbackHUDModule:SetCarryEstimate(math.round(p01 * (maxRange :: number) * cqMult))
			end
		end
		local _swingClubId = ClubManager:GetCurrentClubId()
		print("[ClubPipeline] swing payload clubId=" .. _swingClubId)
		local swingOk, swingErr = pcall(function()
			DeveloperAction:FireServer({
				action      = "ShootBallSwing",
				swingResult = {
					shotPower       = finalResult.shotPower,
					launchDirection = finalResult.launchDirection,
					contactQuality  = finalResult.contactQuality,
					shotShape       = finalResult.shotShape,
					carryMultiplier = finalResult.carryMultiplier,
					rollMultiplier  = finalResult.rollMultiplier,
					sideSpinInput   = finalResult.sideSpinInput,
					backSpinInput   = finalResult.backSpinInput,
					isPutt          = finalResult.isPutt or false,
					clubId          = _swingClubId,
				},
			})
		end)
		if not swingOk then
			warn("[PlayableHole] ShootBallSwing FireServer failed: " .. tostring(swingErr))
		else
			print(("[PlayableHole] Swing fired — contact=%s shape=%s power=%.1f putt=%s"):format(
				finalResult.contactQuality, finalResult.shotShape, finalResult.shotPower,
				tostring(finalResult.isPutt or false)))
		end
	end)

	-- ── Input: Z/X = club, F = start, R = reset, V = devHUD, T = teleport ────────
	local keyConn = UserInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			-- Diagnostic: always print so we can confirm InputBegan fires and see
			-- whether gameProcessed is blocking Z/X.  Remove once club switching works.
			print("[PHCM Input]", input.KeyCode.Name, "processed=", gameProcessed)

			-- Z/X: PHCM is the sole owner of club-switching input.
			-- ClubManager:Init() no longer connects its own InputBegan handler.
			-- We call Cycle unconditionally — gameProcessed is irrelevant here because
			-- there is no other handler that could double-cycle.
			if input.KeyCode == Enum.KeyCode.Z then
				ClubManager:CyclePrev()
				_syncSelectedClub()
				return
			elseif input.KeyCode == Enum.KeyCode.X then
				ClubManager:CycleNext()
				_syncSelectedClub()
				return
			end

			if gameProcessed then return end
			if input.KeyCode == Enum.KeyCode.V then
				-- V toggles the developer HUD overlay
				if _devGui then _devGui.Enabled = not _devGui.Enabled end
			elseif input.KeyCode == Enum.KeyCode.F then
				PlayableHoleControllerModule:StartPlayableHole()
			elseif input.KeyCode == Enum.KeyCode.R then
				PlayableHoleControllerModule:Reset()
			elseif input.KeyCode == Enum.KeyCode.T then
				-- Dev teleport: snap player next to ball; still requires E to address.
				local ball = _findBall()
				if ball then
					print("[PlayableHole] Teleporting to ball")
					pcall(function()
						DeveloperAction:FireServer({ action = "TeleportToBall" })
					end)
					-- After the server moves the character, rebind AddressBallModule so the
					-- E prompt appears once the player is within range.
					-- 0.3 s covers the server round-trip + one physics frame to settle.
					task.spawn(function()
						task.wait(0.3)
						if _status ~= "BallLanded" and _status ~= "HoleReady" then return end
						print("[AddressDebug] TeleportToBall refresh address prompt")
						AddressBallModule:Disable()
						local refreshBall = _findBall()
						if refreshBall then
							AddressBallModule:Enable(refreshBall, function()
								pcall(function()
									DeveloperAction:FireServer({ action = "AddressBall" })
								end)
							end)
						else
							warn("[PlayableHole] TeleportToBall: ball not found — address prompt cannot rebind")
						end
					end)
				else
					print("[PlayableHole] No ball found — press F to start a hole first")
				end
			end
		end
	)
	table.insert(_connections, keyConn)

	-- ── Shift sprint: hold LeftShift to walk faster between shots ─────────────
	local NORMAL_SPEED: number = 16
	local SPRINT_SPEED: number = 26

	local function _setWalkSpeed(speed: number)
		local char = LocalPlayer.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if hum then (hum :: Humanoid).WalkSpeed = speed end
	end

	local shiftDownConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			_setWalkSpeed(SPRINT_SPEED)
		end
	end)
	table.insert(_connections, shiftDownConn)

	local shiftUpConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			_setWalkSpeed(NORMAL_SPEED)
		end
	end)
	table.insert(_connections, shiftUpConn)

	-- Restore normal speed when a new character spawns (e.g. after Reset)
	local respawnConn = LocalPlayer.CharacterAdded:Connect(function(char: Model)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if hum then (hum :: Humanoid).WalkSpeed = NORMAL_SPEED end
	end)
	table.insert(_connections, respawnConn)

	-- ── GameBus listener: sync dev HUD with server state ─────────────────────
	local busConn = GameBus.OnClientEvent:Connect(function(envelope: any)
		if type(envelope) ~= "table" then return end
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.userId ~= LocalPlayer.UserId then return end

		-- ── CupIn: ball captured in cup during rolling ───────────────────────────
		if envelope.eventType == "CupIn" then
			_destroyBallTracker()
			_stopBallCamera(false)
			SwingEngineControllerModule:Stop()
			GolfClubVisualModule:Detach()
			AddressBallModule:Disable()
			PuttingModule:Deactivate()
			GolfHUDModule:SetPuttingMode(false)
			ClubManager:SetLocked(true)
			_puttingMode = false
			return
		end

		-- ── ShotFired: launch FX + HUD feedback text ────────────────────────────
		if envelope.eventType == "ShotFired" then
			local cq: string = if type(payload.contactQuality) == "string"
				then payload.contactQuality :: string else "Good"

			local feedText:  string
			local feedColor: Color3
			if cq == "Perfect" then
				feedText  = "PERFECT!"
				feedColor = Color3.fromRGB(255, 215, 0)
			elseif cq == "Good" then
				feedText  = "GOOD SHOT"
				feedColor = Color3.fromRGB(100, 230, 110)
			elseif cq == "Thin" then
				feedText  = "THIN"
				feedColor = Color3.fromRGB(255, 230, 55)
			elseif cq == "Chunk" then
				feedText  = "CHUNK"
				feedColor = Color3.fromRGB(255, 140, 45)
			elseif cq == "Poor" then
				feedText  = "POOR SHOT"
				feedColor = Color3.fromRGB(255, 155, 80)
			else -- Mishit
				feedText  = "MISHIT"
				feedColor = Color3.fromRGB(255, 80, 80)
			end
			_showFeedback(feedText, feedColor)
			_spawnLaunchFX(cq)
			return
		end

		-- ── DevPlayState: HUD state sync ────────────────────────────────────────
		if envelope.eventType ~= "DevPlayState" then return end
		if type(payload.status) == "string" then
			_status = payload.status :: string
		end
		if type(payload.strokes) == "number" then
			_strokes = payload.strokes :: number
		end
		_updateDevHUD()
		-- Sync ball state to swing debug HUD (ball phase column)
		SwingFeedbackHUDModule:SetBallState(_statusToBallState(_status))

		-- ── GolfHUD + ClubHUD: always update strokes + ball state ───────────────
		GolfHUDModule:SetStrokes(_strokes)
		GolfHUDModule:SetBallState(_statusToBallState(_status))
		if type(payload.distance) == "number" then
			local dist  = payload.distance :: number
			_lastDist   = dist
			GolfHUDModule:SetDistance(dist)
			ClubHUDModule:SetDistance(dist)
		end
		if type(payload.lie) == "string" then
			local lieStr = payload.lie :: string
			_lastLie     = lieStr
			GolfHUDModule:SetLie(lieStr)
			ClubHUDModule:SetLie(lieStr)
		end

		-- ── Per-state logic ───────────────────────────────────────────────────────
		if _status == "HoleReady" then
			if payload.addressed == true then
				-- Cancel any camera automation so Follow mode is clean for the swing
				_stopBallCamera(false)
				if _camIntroConn then _camIntroConn:Disconnect(); _camIntroConn = nil end
				-- Re-sync putting mode from server on address
				local pMode2 = payload.puttingMode == true
				_puttingMode = pMode2
				if pMode2 then
					PuttingModule:Activate()
					ClubManager:SetClub("PUTTER")
					print("[Club] Putting mode — locked to PUTTER")
				else
					PuttingModule:Deactivate()
				end
				GolfHUDModule:SetPuttingMode(pMode2)
				-- Lock club cycling for the duration of the swing
				ClubManager:SetLocked(true)
				-- Show landing prediction disc + power meter until the ball launches
				_showLandingMarker()
				_showSwingMeter()
				-- After address: swing engine on, attach club
				SwingEngineControllerModule:Start()
				local character = LocalPlayer.Character
				if character then
					GolfClubVisualModule:AttachToCharacter(character)
				end
			else
				-- Hole start / pre-address: unlock club cycling so player can choose while walking
				ClubManager:SetLocked(false)
				-- Hole start: proximity check so player can walk to ball and press E
				AddressBallModule:Disable()
				task.spawn(function()
					task.wait(0.35)   -- let ball replicate before searching
					-- Camera intro fires only on the first HoleReady per session
					if _firstHoleReady then
						_firstHoleReady = false
						_doTeeIntroCamera()
					end
					local ball = _findBall()
					if ball then
						AddressBallModule:Enable(ball, function()
							pcall(function()
								DeveloperAction:FireServer({ action = "AddressBall" })
							end)
						end)
					else
						warn("[PlayableHole] HoleReady: ball not found in Workspace — check replication")
					end
				end)
			end

		elseif _status == "ShotInProgress" then
			_hideLandingMarker()
			_hideSwingMeter()
			ClubManager:SetLocked(true)
			AddressBallModule:Disable()
			-- Start ball-tracking camera immediately, then attach the HUD tracker
			_startBallCamera()
			task.spawn(function()
				task.wait(0.1)  -- brief wait for ball to move off the ground
				_destroyBallTracker()
				local ball = _findBall()
				if ball then
					_ballTrackerGui = _createBallTracker(ball)
				end
			end)

		elseif _status == "BallLanded" then
			_hideLandingMarker()
			_hideSwingMeter()
			-- Landing VFX: dust puff at ball resting position
			local landedBall = _findBall()
			if landedBall then
				_spawnLandingVFX(landedBall.Position)
				SFXPlayer:PlayLanding()
			end
			-- Keep tracker for 2 s so player can see where ball landed, then remove it.
			-- Camera returns behind character (smooth ~1.2 s) → Follow mode.
			task.delay(2.0, _destroyBallTracker)
			_stopBallCamera(true)
			SwingEngineControllerModule:Stop()
			GolfClubVisualModule:Detach()
			AddressBallModule:Disable()
			-- Unlock club cycling; player walks to ball and selects club
			ClubManager:SetLocked(false)
			-- Sync putting mode from server payload
			local pMode = payload.puttingMode == true
			_puttingMode = pMode
			if pMode then
				PuttingModule:Activate()
				ClubManager:SetClub("PUTTER")
				print("[Club] Putting mode — locked to PUTTER")
				ClubManager:SetLocked(true)  -- locked to putter while in putting range
			else
				PuttingModule:Deactivate()
			end
			GolfHUDModule:SetPuttingMode(pMode)
			print("[AddressDebug] BallLanded rebinding address ball")
			local ball = _findBall()
			if ball then
				AddressBallModule:Enable(ball, function()
					pcall(function()
						DeveloperAction:FireServer({ action = "AddressBall" })
					end)
				end)
			else
				warn("[PlayableHole] BallLanded: ball not found — address prompt will not appear")
			end

		elseif _status == "HoleComplete" or _status == "RoundComplete" then
			_hideLandingMarker()
			_hideSwingMeter()
			_destroyBallTracker()
			_stopBallCamera(false)
			SwingEngineControllerModule:Stop()
			AddressBallModule:Disable()
			GolfClubVisualModule:Detach()
			PuttingModule:Deactivate()
			GolfHUDModule:SetPuttingMode(false)
			_puttingMode = false
			if _status == "HoleComplete" then
				HoleCompleteModule:Show(HOLE_NUM, HOLE_PAR, _strokes, {
					onPlayAgain = function()
						PlayableHoleControllerModule:Reset()
						task.wait(0.1)
						PlayableHoleControllerModule:StartPlayableHole()
					end,
					onContinue = function()
						PlayableHoleControllerModule:Reset()
					end,
				})
			end
		end
	end)
	table.insert(_connections, busConn)

	local hudOk, hudErr = pcall(_buildDevHUD)
	if not hudOk then
		warn("[PlayableHole] DevPlayHUD build failed: " .. tostring(hudErr))
	end

	print("[PlayableHole] client ready — F=Start, Drag=Swing, Space=FaceControl, R=Reset, V=DevHUD")
end

function PlayableHoleControllerModule:IsInitialized(): boolean
	return _initialized
end

function PlayableHoleControllerModule:Update(_dt: number) end

function PlayableHoleControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	if _camIntroConn then
		_camIntroConn:Disconnect()
		_camIntroConn = nil
	end

	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Follow
	end

	if _feedbackConn   then _feedbackConn:Disconnect();   _feedbackConn   = nil end
	if _shakeConn      then _shakeConn:Disconnect();      _shakeConn      = nil end
	if _ballCamConn    then _ballCamConn:Disconnect();    _ballCamConn    = nil end
	if _ballCamRtnConn then _ballCamRtnConn:Disconnect(); _ballCamRtnConn = nil end
	_destroyBallTracker()
	_stopBallCamera(false)

	_hideLandingMarker()
	_hideSwingMeter()
	_lastLie  = "Tee"
	_lastDist = 0

	if _devGui and _devGui.Parent then _devGui:Destroy() end
	_devGui       = nil
	_lblState     = nil
	_lblBallState = nil
	_lblFeedback  = nil
	_lblDevClub   = nil
	_lblDevLie    = nil
	_lblDevDist   = nil
	_lblDevCarry  = nil
	_lblDevCam    = nil
	_lblDevPutt   = nil

	PuttingModule:Deactivate()
	HoleCompleteModule:Destroy()
	AddressBallModule:Destroy()
	GolfHUDModule:Destroy()
	GolfClubVisualModule:Destroy()
	SwingEngineControllerModule:Destroy()
	ClubManager:Destroy()
	ClubHUDModule:Destroy()

	_status         = "Idle"
	_strokes        = 0
	_lastInput      = ""
	_firstHoleReady = true
	_puttingMode    = false
	_initialized    = false
end

return PlayableHoleControllerModule
