--!strict
-- InputControllerModule — Client singleton logic
-- Contains all InputController state and handlers as a requireable module so
-- Sprint6ClientTest can call _onClientEvent / _onInputBegan directly without
-- a live network session. InputController.client.lua is the thin runner.
--
-- input parameter typed as `any` in _onInputBegan so tests can pass a plain
-- table ({ KeyCode=..., UserInputType=... }) instead of a real InputObject.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Module state ────────────────────────────────────────────────────────────

local _initialized:    boolean                  = false
local _currentState:   string                   = "LOBBY"
local _holeReadyFired: boolean                  = false
local _connections:    { RBXScriptConnection }  = {}

-- ── Module ─────────────────────────────────────────────────────────────────

local InputControllerModule = {}
InputControllerModule.__index = InputControllerModule

-- ── Private ─────────────────────────────────────────────────────────────────

local function _fireHoleReady()
	if _holeReadyFired then return end
	_holeReadyFired = true
	print(("[InputController] HoleReady → server (player: %s)"):format(LocalPlayer.Name))
	GameBus:FireServer({
		eventType = "HoleReady",
		payload   = {},
		timestamp = os.time(),
	})
end

-- ── Semi-public: exposed for Sprint6ClientTest ───────────────────────────────

-- Simulate a server → client StateChanged without a live GameBus connection.
-- In production this is called by the OnClientEvent listener set up in Init().
function InputControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	if envelope.eventType ~= "StateChanged" then return end

	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= LocalPlayer.UserId then return end

	local newState: string = tostring(payload.state)
	_currentState = newState
	print(("[InputController] state → %q"):format(newState))

	-- Re-arm the debounce each time we enter TEE_OFF (once per shot/hole).
	if newState == "TEE_OFF" then
		_holeReadyFired = false
	end
end

-- Simulate a keyboard/mouse input event. In production `input` is a real
-- InputObject; tests pass a plain table with KeyCode and UserInputType fields.
function InputControllerModule:_onInputBegan(input: any, gameProcessed: boolean)
	if gameProcessed then return end
	if _currentState ~= "TEE_OFF" then return end

	if input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Return
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		_fireHoleReady()
	end

	-- TODO (mobile): handle Enum.UserInputType.Touch once SwingController
	-- and on-screen HUD buttons are implemented.
end

-- ── Getters for tests ────────────────────────────────────────────────────────

function InputControllerModule:GetState(): string
	return _currentState
end

function InputControllerModule:IsHoleReadyFired(): boolean
	return _holeReadyFired
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function InputControllerModule:Init()
	if _initialized then
		warn("[InputController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections, GameBus.OnClientEvent:Connect(function(envelope: any)
		InputControllerModule:_onClientEvent(envelope)
	end))
	table.insert(_connections, UserInputService.InputBegan:Connect(function(
		input: InputObject, gameProcessed: boolean)
		InputControllerModule:_onInputBegan(input, gameProcessed)
	end))

	print(("[InputController] ready (player: %s)"):format(LocalPlayer.Name))
end

function InputControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	_initialized    = false
	_holeReadyFired = false
	_currentState   = "LOBBY"
end

return InputControllerModule
