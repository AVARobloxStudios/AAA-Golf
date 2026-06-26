--!strict
-- PredictionControllerModule — Client singleton (Sprint 7)
-- Receives server ball positions via the loss-tolerant BallPositionStream
-- (UnreliableRemoteEvent, ~60 Hz) and linearly extrapolates the visual ball
-- between packets on RenderStepped.
-- Receives BallResolved via GameBus and clears the snapshot when the ball lands.
--
-- Does NOT create or destroy ball models; those are owned by the server BallPool.
-- PredictionController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LocalPlayer: Player = Players.LocalPlayer

local BallPositionStream: UnreliableRemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.BallPositionStream :: UnreliableRemoteEvent
local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Types ────────────────────────────────────────────────────────────────────

-- Snapshot of the most recent server broadcast for one ball.
type BallSnapshot = {
	ballId:     string,
	pos:        Vector3,
	vel:        Vector3,
	receivedAt: number,   -- os.clock() at the moment the packet arrived
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                    = false
local _snapshots:   { [string]: BallSnapshot? } = {}   -- keyed by ballId
local _connections: { RBXScriptConnection }    = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local PredictionControllerModule = {}
PredictionControllerModule.__index = PredictionControllerModule

-- ── Private ───────────────────────────────────────────────────────────────────

-- Searches Workspace.ActiveBalls for the Model whose OwnerValue points to the
-- player that owns the given ballId ("ball_<userId>").
local function _findBall(ballId: string): Model?
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
		local player = owner :: Player
		if ("ball_" .. tostring(player.UserId)) == ballId then
			return model
		end
	end
	return nil
end

-- Runs every RenderStepped. For each tracked ball, extrapolates its position
-- using the last known velocity and the elapsed time since the snapshot arrived,
-- then applies that position to the visual Model's PrimaryPart CFrame.
local function _onRenderStepped(_dt: number)
	local now = os.clock()
	for ballId, snap in pairs(_snapshots) do
		if not snap then continue end
		local elapsed   = now - snap.receivedAt
		local predicted = snap.pos + snap.vel * elapsed
		local model     = _findBall(ballId)
		if not model then continue end
		local part = model.PrimaryPart
		if not part then continue end
		part.CFrame = CFrame.new(predicted)
	end
end

-- ── Semi-public: exposed for Sprint7ClientTest ────────────────────────────────

-- Handles a raw BallPositionStream packet.
-- payload is the table fired directly by PhysicsService:_broadcastPosition:
--   { ballId: string, pos: Vector3, vel: Vector3 }
function PredictionControllerModule:_onBallPositionUpdate(payload: any)
	if type(payload) ~= "table" then return end

	local ballId = payload.ballId
	if type(ballId) ~= "string" then return end

	local pos = payload.pos
	if typeof(pos) ~= "Vector3" then return end

	local vel: Vector3 = if typeof(payload.vel) == "Vector3"
		then payload.vel :: Vector3
		else Vector3.zero

	_snapshots[ballId] = {
		ballId     = ballId,
		pos        = pos,
		vel        = vel,
		receivedAt = os.clock(),
	}

	print(("[PredictionController] BallPositionStream | ballId=%s pos=%s vel=%s"):format(
		ballId, tostring(pos), tostring(vel)))
end

-- Handles a GameBus BallResolved envelope.payload.
-- Clears the snapshot; the server has already returned the ball to BallPool.
function PredictionControllerModule:_onBallResolved(payload: any)
	if type(payload) ~= "table" then return end

	local ballId = payload.ballId
	if type(ballId) ~= "string" then return end

	local landingPos  = payload.landingPos
	local surface     = payload.landingSurface

	print(("[PredictionController] BallResolved | ballId=%s landingPos=%s surface=%s"):format(
		ballId,
		if typeof(landingPos) == "Vector3" then tostring(landingPos) else "?",
		if type(surface) == "string" then surface else "?"
	))

	_snapshots[ballId] = nil
end

-- Filters incoming GameBus envelopes; routes BallResolved to _onBallResolved.
function PredictionControllerModule:_onGameBusEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	if envelope.eventType ~= "BallResolved" then return end
	self:_onBallResolved(envelope.payload)
end

-- ── Getters for Sprint7ClientTest ─────────────────────────────────────────────

-- Returns the most recent snapshot for ballId, or nil if none exists.
function PredictionControllerModule:GetSnapshot(ballId: string): BallSnapshot?
	return _snapshots[ballId]
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PredictionControllerModule:Init()
	if _initialized then
		warn("[PredictionController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		BallPositionStream.OnClientEvent:Connect(function(payload: any)
			PredictionControllerModule:_onBallPositionUpdate(payload)
		end))

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			PredictionControllerModule:_onGameBusEvent(envelope)
		end))

	table.insert(_connections,
		RunService.RenderStepped:Connect(_onRenderStepped))

	print(("[PredictionController] ready (player: %s)"):format(LocalPlayer.Name))
end

function PredictionControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(_snapshots)
	_initialized = false
end

return PredictionControllerModule
