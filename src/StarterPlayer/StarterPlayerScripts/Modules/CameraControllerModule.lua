--!strict
-- CameraControllerModule — Client singleton (Sprint 8)
-- Manages workspace.CurrentCamera based on game-state events received
-- via GameBus StateChanged envelopes.  Camera is only modified while the
-- local player is in an active round; Destroy() restores whatever camera
-- settings existed before Init() was called.
--
-- Camera modes
--   LOBBY           → Custom (Roblox default, restored from snapshot)
--   TEE_OFF / SWING → Scriptable, positioned behind the character
--   BALL_IN_FLIGHT  → Scriptable, follows the player's active ball
--   SCORE_REVEAL    → Scriptable, looks down at the stored landing position
--
-- CameraController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- Stable per-session ball id for the local player.
local MY_BALL_ID: string = "ball_" .. tostring(LocalPlayer.UserId)

-- ── Types ────────────────────────────────────────────────────────────────────

-- Snapshot of Camera properties taken at Init() and restored by Destroy().
type SavedCamera = {
	cameraType:    Enum.CameraType,
	cameraSubject: Instance?,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:  boolean                  = false
local _currentState: string                   = "LOBBY"
local _savedCamera:  SavedCamera?             = nil
local _landingPos:   Vector3?                 = nil   -- from most recent BallResolved
local _connections:  { RBXScriptConnection }  = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local CameraControllerModule = {}
CameraControllerModule.__index = CameraControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- Returns the PrimaryPart of the local player's active ball, or nil.
local function _findActiveBall(): BasePart?
	local folder = workspace:FindFirstChild("ActiveBalls")
	if not folder then return nil end

	for _, child in ipairs(folder:GetChildren()) do
		if not child:IsA("Model") then continue end
		local model = child :: Model
		local ov = model:FindFirstChild("OwnerValue") :: ObjectValue?
		if not ov then continue end
		local owner = ov.Value
		if not owner then continue end
		if not owner:IsA("Player") then continue end
		local plr = owner :: Player
		if plr ~= LocalPlayer then continue end
		return model.PrimaryPart
	end
	return nil
end

-- Aim CFrame: 12 studs behind and 5 above the HumanoidRootPart, looking at
-- the character's neck height.
local function _getAimCFrame(): CFrame?
	local char = LocalPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return nil end

	local look   = hrp.CFrame.LookVector
	local camPos = hrp.Position - look * 12 + Vector3.new(0, 5, 0)
	return CFrame.lookAt(camPos, hrp.Position + Vector3.new(0, 1, 0))
end

-- Follow CFrame: 8 studs above and 12 studs behind the ball's travel direction.
-- Falls back to a fixed overhead offset when the ball's direction is negligible.
local function _getFollowBallCFrame(): CFrame?
	local part = _findActiveBall()
	if not part then return nil end

	local ballPos = part.Position
	local camPos  = ballPos + Vector3.new(0, 8, 12)
	return CFrame.lookAt(camPos, ballPos + Vector3.new(0, 1, 0))
end

-- Score-reveal CFrame: above and slightly behind the landing position.
local function _getScoreRevealCFrame(): CFrame?
	if not _landingPos then return nil end
	local camPos = _landingPos + Vector3.new(0, 15, -10)
	return CFrame.lookAt(camPos, _landingPos)
end

-- Applies camera type and CFrame for the given game state.
-- Guarded by workspace.CurrentCamera nil-check; gracefully skips CFrame
-- assignment if character/ball data is not yet available.
local function _applyCameraForState(state: string)
	local cam = workspace.CurrentCamera
	if not cam then return end

	if state == "LOBBY" then
		-- Restore the pre-Init camera snapshot, or fall back to default.
		if _savedCamera then
			cam.CameraType    = _savedCamera.cameraType
			cam.CameraSubject = _savedCamera.cameraSubject :: any
		else
			cam.CameraType = Enum.CameraType.Custom
		end

	elseif state == "TEE_OFF" or state == "SWING" then
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = _getAimCFrame()
		if cf then cam.CFrame = cf end

	elseif state == "BALL_IN_FLIGHT" then
		cam.CameraType = Enum.CameraType.Scriptable
		-- Initial placement; RenderStepped drives per-frame updates.
		local cf = _getFollowBallCFrame()
		if cf then cam.CFrame = cf end

	elseif state == "SCORE_REVEAL" then
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = _getScoreRevealCFrame()
		if cf then cam.CFrame = cf end
	end
end

-- RenderStepped handler: only active in BALL_IN_FLIGHT, smoothly tracks the ball.
local function _onRenderStepped(_dt: number)
	if _currentState ~= "BALL_IN_FLIGHT" then return end
	local cam = workspace.CurrentCamera
	if not cam then return end

	local cf = _getFollowBallCFrame()
	if cf then cam.CFrame = cf end
end

-- ── Semi-public: exposed for Sprint8ClientTest ───────────────────────────────

-- Routes incoming GameBus envelopes.
-- Handles StateChanged (updates mode) and BallResolved (stores landing pos).
-- Envelope format: { eventType: string, payload: any, timestamp: number }
function CameraControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end

	-- ── BallResolved ─────────────────────────────────────────────────────────
	if envelope.eventType == "BallResolved" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.ballId ~= MY_BALL_ID then return end
		if typeof(payload.landingPos) ~= "Vector3" then return end
		_landingPos = payload.landingPos :: Vector3
		Logger:Debug("CameraController", ("BallResolved — landing stored at %s"):format(
			tostring(_landingPos)))
		return
	end

	-- ── StateChanged ─────────────────────────────────────────────────────────
	if envelope.eventType ~= "StateChanged" then return end

	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= LocalPlayer.UserId then return end

	local newState: string = tostring(payload.state)
	if newState == _currentState then return end

	Logger:Debug("CameraController", ("state → %q"):format(newState))

	-- Clear stale landing data when a new shot begins.
	if newState == "BALL_IN_FLIGHT" then
		_landingPos = nil
	end

	_currentState = newState
	_applyCameraForState(newState)
end

-- ── Getters for Sprint8ClientTest ─────────────────────────────────────────────

function CameraControllerModule:GetState(): string
	return _currentState
end

function CameraControllerModule:GetLandingPos(): Vector3?
	return _landingPos
end

function CameraControllerModule:IsInitialized(): boolean
	return _initialized
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function CameraControllerModule:Init()
	if _initialized then
		warn("[CameraController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Snapshot current camera settings so Destroy() can restore them exactly.
	local cam = workspace.CurrentCamera
	if cam then
		_savedCamera = {
			cameraType    = cam.CameraType,
			cameraSubject = cam.CameraSubject :: Instance?,
		}
	end

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			CameraControllerModule:_onClientEvent(envelope)
		end))

	table.insert(_connections,
		RunService.RenderStepped:Connect(_onRenderStepped))

	Logger:Info("CameraController", ("ready (player: %s)"):format(LocalPlayer.Name))
end

function CameraControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	-- Restore camera to exactly the state it was in before Init().
	local cam = workspace.CurrentCamera
	if cam and _savedCamera then
		cam.CameraType    = _savedCamera.cameraType
		cam.CameraSubject = _savedCamera.cameraSubject :: any
	end

	_savedCamera  = nil
	_landingPos   = nil
	_currentState = "LOBBY"
	_initialized  = false
end

return CameraControllerModule
