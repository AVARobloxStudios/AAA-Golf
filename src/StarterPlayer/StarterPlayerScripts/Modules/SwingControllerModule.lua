--!strict
-- SwingControllerModule — Client singleton logic for the swing mechanic.
-- Hold Space or MouseButton1 to charge power; release to fire SwingIntent.
-- All state in module-level locals; exposed via getter methods for tests.
-- SwingController.client.lua is the thin runner.
--
-- Power: time held / MAX_CHARGE_TIME, clamped [0, 1].
-- AimVector: camera LookVector flattened to XZ, normalized.
-- ClubId: "DRIVER" (default; future sprint wires club selection UI).
-- SpinVector: Vector3.zero (future sprint wires topspin/sidespin controls).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Constants ────────────────────────────────────────────────────────────────

local MAX_CHARGE_TIME  = 2.0      -- seconds for full power
local DEFAULT_CLUB_ID  = "DRIVER" -- must match ClubData.Clubs key (uppercase)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean                 = false
local _currentState:  string                  = "LOBBY"
local _swingFired:    boolean                 = false
local _charging:      boolean                 = false
local _chargeStart:   number                  = 0
local _connections:   { RBXScriptConnection } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingControllerModule = {}
SwingControllerModule.__index = SwingControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _getAimVector(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then
		-- Camera pointing straight up or down — fall back to -Z.
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function _getPower(): number
	return math.clamp((os.clock() - _chargeStart) / MAX_CHARGE_TIME, 0, 1)
end

local function _fireSwingIntent()
	if not _charging then return end
	local power     = _getPower()   -- sample BEFORE clearing _charging
	_charging    = false
	_swingFired  = true

	local aimVector = _getAimVector()
	local clubId    = DEFAULT_CLUB_ID

	print(("[SwingController] SwingIntent → server | power=%.2f clubId=%s aim=%s"):format(
		power, clubId, tostring(aimVector)))

	GameBus:FireServer({
		eventType = "SwingIntent",
		payload   = {
			aimVector  = aimVector,
			power      = power,
			accuracy   = 0.0,         -- TODO: accuracy mechanic (future sprint)
			clubId     = clubId,
			spinVector = Vector3.zero, -- TODO: topspin/sidespin controls
			timestamp  = os.time(),
		},
		timestamp = os.time(),
	})
end

-- ── Semi-public: exposed for Sprint6ClientTest ────────────────────────────────

-- Simulate a server StateChanged without a live GameBus connection.
-- In production this is called via the OnClientEvent listener in Init().
function SwingControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	if envelope.eventType ~= "StateChanged" then return end

	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= LocalPlayer.UserId then return end

	local newState: string = tostring(payload.state)
	_currentState = newState
	print(("[SwingController] state → %q"):format(newState))

	if newState == "SWING" then
		-- Re-arm for this shot: allow a fresh charge cycle.
		_swingFired = false
		_charging   = false
	end
end

-- input: any so tests can pass a plain table { KeyCode=..., UserInputType=... }
-- instead of a real InputObject.
function SwingControllerModule:_onInputBegan(input: any, gameProcessed: boolean)
	if gameProcessed then return end
	if _currentState ~= "SWING" then return end
	if _swingFired  then return end   -- already fired this SWING state
	if _charging    then return end   -- already charging; ignore re-press

	if input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		_charging    = true
		_chargeStart = os.clock()
		print("[SwingController] charge started")
	end
end

-- gameProcessed not checked on release: we always want to process the
-- release of our own charge even if a UI element consumed the begin event.
function SwingControllerModule:_onInputEnded(input: any)
	if not _charging then return end
	if _currentState ~= "SWING" then return end

	if input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		_fireSwingIntent()
	end
end

-- ── Getters for tests ────────────────────────────────────────────────────────

function SwingControllerModule:GetState(): string
	return _currentState
end

function SwingControllerModule:IsSwingFired(): boolean
	return _swingFired
end

function SwingControllerModule:IsCharging(): boolean
	return _charging
end

-- Returns the current charge power [0,1], or 0 when not charging.
function SwingControllerModule:GetPower(): number
	if not _charging then return 0 end
	return _getPower()
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SwingControllerModule:Init()
	if _initialized then
		warn("[SwingController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections, GameBus.OnClientEvent:Connect(function(envelope: any)
		SwingControllerModule:_onClientEvent(envelope)
	end))
	table.insert(_connections, UserInputService.InputBegan:Connect(function(
		input: InputObject, gp: boolean)
		SwingControllerModule:_onInputBegan(input, gp)
	end))
	table.insert(_connections, UserInputService.InputEnded:Connect(function(
		input: InputObject, _gp: boolean)
		SwingControllerModule:_onInputEnded(input)
	end))

	print(("[SwingController] ready (player: %s)"):format(LocalPlayer.Name))
end

function SwingControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	_initialized  = false
	_swingFired   = false
	_charging     = false
	_currentState = "LOBBY"
end

return SwingControllerModule
