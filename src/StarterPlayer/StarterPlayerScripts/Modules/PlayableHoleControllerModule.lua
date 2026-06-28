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

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Logger)

-- Sprint 34.5: swing orchestration delegated to SwingEngineControllerModule
local SwingEngineControllerModule = require(script.Parent.SwingEngineControllerModule)

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

local _initialized: boolean               = false
local _status:      string                = "Idle"
local _lastInput:   string                = ""
local _aimDir:      Vector3               = Vector3.new(0, 0, -1)
local _strokes:     number                = 0
local _connections: { RBXScriptConnection } = {}
local _devGui:      ScreenGui?            = nil
local _lblState:    TextLabel?            = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local PlayableHoleControllerModule = {}
PlayableHoleControllerModule.__index = PlayableHoleControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _updateDevHUD()
	if not _lblState then return end
	_lblState.Text = ("State: %s  |  Strokes: %d"):format(_status, _strokes)
end

local function _buildDevHUD()
	local playerGui: PlayerGui = LocalPlayer.PlayerGui

	-- Only destroy the HUD this module instance previously created.
	-- Never destroy by name — a concurrent module instance (e.g. TestRunner's PHCM
	-- copy) may have created a same-named HUD in the same PlayerGui.
	if _devGui and _devGui.Parent then
		_devGui:Destroy()
	end

	local screenGui               = Instance.new("ScreenGui")
	screenGui.Name                = "DevPlayHUD"
	screenGui.ResetOnSpawn        = false
	screenGui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder        = 99

	local frame                   = Instance.new("Frame")
	frame.BackgroundColor3        = Color3.fromRGB(10, 10, 10)
	frame.BackgroundTransparency  = 0.35
	frame.Size                    = UDim2.new(0, 310, 0, 80)
	frame.Position                = UDim2.new(0, 10, 1, -96)
	frame.AnchorPoint             = Vector2.new(0, 1)
	frame.BorderSizePixel         = 0
	frame.Parent                  = screenGui

	local function makeLabel(
		text:  string,
		posY:  number,
		bold:  boolean,
		color: Color3
	): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size          = UDim2.new(1, -16, 0, 20)
		lbl.Position      = UDim2.new(0, 8, 0, posY)
		lbl.Font          = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		lbl.TextSize      = if bold then 13 else 12
		lbl.TextColor3    = color
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate   = Enum.TextTruncate.AtEnd
		lbl.Text          = text
		lbl.Parent        = frame
		return lbl
	end

	makeLabel("[ DEV GOLF TEST ]", 6, true, Color3.fromRGB(255, 200, 50))
	_lblState = makeLabel("State: Idle  |  Strokes: 0", 26, false, Color3.fromRGB(220, 220, 220))
	makeLabel("F=Start  Drag=Swing  Space=Face  R=Reset", 50, false, Color3.fromRGB(160, 160, 160))

	screenGui.Parent = LocalPlayer.PlayerGui
	_devGui = screenGui
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
	SwingEngineControllerModule:Start()
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
	_status    = "Idle"
	_strokes   = 0
	_lastInput = "Reset"
	_updateDevHUD()
	SwingEngineControllerModule:Stop()
	SwingEngineControllerModule:Reset()
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
	_initialized = true
	_status      = "Idle"
	_strokes     = 0
	_lastInput   = ""
	_aimDir      = Vector3.new(0, 0, -1)

	-- ── SwingEngine setup ─────────────────────────────────────────────────────
	SwingEngineControllerModule:Init()

	SwingEngineControllerModule:SetAimDirectionProvider(function(): Vector3
		local camera = Workspace.CurrentCamera
		return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	end)

	SwingEngineControllerModule:SetSwingResultCallback(function(swingResult: any)
		-- Gate: only send to server in shootable states
		if _status ~= "HoleReady" and _status ~= "BallLanded" then return end
		_aimDir    = swingResult.launchDirection
		_lastInput = "Swing"
		_updateDevHUD()
		local swingOk, swingErr = pcall(function()
			DeveloperAction:FireServer({
				action      = "ShootBallSwing",
				swingResult = {
					shotPower       = swingResult.shotPower,
					launchDirection = swingResult.launchDirection,
					contactQuality  = swingResult.contactQuality,
					shotShape       = swingResult.shotShape,
					carryMultiplier = swingResult.carryMultiplier,
					rollMultiplier  = swingResult.rollMultiplier,
					sideSpinInput   = swingResult.sideSpinInput,
					backSpinInput   = swingResult.backSpinInput,
				},
			})
		end)
		if not swingOk then
			warn("[PlayableHole] ShootBallSwing FireServer failed: " .. tostring(swingErr))
		else
			print(("[PlayableHole] Swing fired — contact=%s shape=%s power=%.1f"):format(
				swingResult.contactQuality, swingResult.shotShape, swingResult.shotPower))
		end
	end)

	-- ── Input: F = start, R = reset (swing input now owned by SwingEngine) ────
	local keyConn = UserInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then return end
			if input.KeyCode == Enum.KeyCode.F then
				PlayableHoleControllerModule:StartPlayableHole()
			elseif input.KeyCode == Enum.KeyCode.R then
				PlayableHoleControllerModule:Reset()
			end
		end
	)
	table.insert(_connections, keyConn)

	-- ── GameBus listener: sync dev HUD with server state ─────────────────────
	local busConn = GameBus.OnClientEvent:Connect(function(envelope: any)
		if type(envelope) ~= "table" then return end
		if envelope.eventType ~= "DevPlayState" then return end
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.userId ~= LocalPlayer.UserId then return end
		if type(payload.status) == "string" then
			_status = payload.status :: string
		end
		if type(payload.strokes) == "number" then
			_strokes = payload.strokes :: number
		end
		_updateDevHUD()
	end)
	table.insert(_connections, busConn)

	local hudOk, hudErr = pcall(_buildDevHUD)
	if not hudOk then
		warn("[PlayableHole] DevPlayHUD build failed: " .. tostring(hudErr))
	end

	print("[PlayableHole] client ready — F=Start, Drag=Swing, Space=FaceControl, R=Reset")
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

	if _devGui and _devGui.Parent then
		_devGui:Destroy()
	end
	_devGui   = nil
	_lblState = nil

	SwingEngineControllerModule:Destroy()

	_status      = "Idle"
	_strokes     = 0
	_lastInput   = ""
	_initialized = false
end

return PlayableHoleControllerModule
