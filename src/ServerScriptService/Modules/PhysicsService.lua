--!strict
-- PhysicsService — Server-only ModuleScript
-- Authoritative ball simulation at ~60Hz. The sole writer of PrimaryPart.CFrame
-- on the server. Clients receive positions via BallPositionStream (UnreliableRE)
-- and reconcile ShadowPhysicsIntegrator predictions on BallResolved (GameBus).
-- TDD §4.2, §14.2, §14.3.

local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types             = require(ReplicatedStorage.Shared.Modules.Types)
local PhysicsIntegrator = require(ServerScriptService.Modules.PhysicsIntegrator)
local BallPool          = require(ServerScriptService.Modules.BallPool)

-- ── Network ────────────────────────────────────────────────────────────────

-- BallPositionStream: UnreliableRemoteEvent — loss-tolerant 60Hz position push.
-- GameBus: RemoteEvent — reliable envelope bus for BallResolved and other events.
local BallPositionStream: UnreliableRemoteEvent =
    ReplicatedStorage.Network.RemoteEvents.BallPositionStream :: UnreliableRemoteEvent
local GameBus: RemoteEvent =
    ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Types ──────────────────────────────────────────────────────────────────

type BallPhysState = Types.BallPhysState

-- One entry per active ball (one ball per player).
-- ActiveBall? because entries are removed by setting the key to nil.
type ActiveBall = {
	id:         string,         -- "ball_<userId>"; stable for this shot's lifetime
	player:     Player,
	model:      Model,          -- leased from BallPool; returned in _finalizeFlight
	physState:  BallPhysState,
	trajectory: { Vector3 },   -- every simulated position; sent in BallResolved
	inFlight:   boolean,
}

-- ── Module state ───────────────────────────────────────────────────────────

local _activeBalls:   { [number]: ActiveBall? } = {}  -- keyed by player.UserId
local _heartbeatConn: RBXScriptConnection?      = nil

-- ── Module ─────────────────────────────────────────────────────────────────

local PhysicsService = {}
PhysicsService.__index = PhysicsService

-- ── Private ────────────────────────────────────────────────────────────────

-- Sends current position + velocity to all clients on the loss-tolerant channel.
function PhysicsService:_broadcastPosition(ball: ActiveBall)
	BallPositionStream:FireAllClients({
		ballId = ball.id,
		pos    = ball.physState.pos,
		vel    = ball.physState.vel,
	})
end

-- Finalizes a ball's flight: marks it SETTLED, fires BallResolved to all
-- clients, then releases the model back to BallPool.
-- Called only from OnHeartbeat after CheckLanding returns true.
-- Sprint 3 will insert HazardResolver + ScoringService:CommitStroke here.
function PhysicsService:_finalizeFlight(ball: ActiveBall)
	-- Briefly mark SETTLED before BallPool:Release resets StateValue to IDLE.
	-- Sprint 3 code will read SETTLED to trigger hole-decision logic.
	local sv = ball.model:FindFirstChild("StateValue") :: StringValue?
	if sv then
		sv.Value = "SETTLED"
	end

	-- Notify all clients: authoritative landing position + full trajectory.
	-- landingSurface is UNKNOWN until HazardResolver is wired in Sprint 3.
	GameBus:FireAllClients({
		eventType = "BallResolved",
		payload   = {
			ballId         = ball.id,
			trajectory     = ball.trajectory,
			landingPos     = ball.physState.pos,
			landingSurface = "UNKNOWN",
		},
		timestamp = os.time(),
	})

	BallPool:Release(ball.model)             -- resets StateValue → IDLE, OwnerValue → nil
	_activeBalls[ball.player.UserId] = nil
end

-- Advances every in-flight ball one RK4 step, updates its visual CFrame,
-- broadcasts the new position, and checks for landing.
-- Balls that land this tick are collected before mutation to avoid modifying
-- _activeBalls during the pairs traversal.
function PhysicsService:OnHeartbeat(dt: number)
	local toFinalize: { ActiveBall } = {}

	for _, ball in pairs(_activeBalls) do
		if not ball or not ball.inFlight then continue end

		ball.physState = PhysicsIntegrator:Step(ball.physState, dt)
		table.insert(ball.trajectory, ball.physState.pos)

		local part = ball.model.PrimaryPart
		if part then
			part.CFrame = CFrame.new(ball.physState.pos)
		end

		self:_broadcastPosition(ball)

		if PhysicsIntegrator:CheckLanding(ball.physState) then
			ball.inFlight = false
			table.insert(toFinalize, ball)
		end
	end

	for _, ball in ipairs(toFinalize) do
		self:_finalizeFlight(ball)
	end
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function PhysicsService:Init(_dependencies: { [string]: any })
	-- Guard: prevent duplicate Heartbeat connections if Init is called twice.
	if _heartbeatConn then
		warn("[PhysicsService] Init called while already initialised — skipping")
		return
	end

	-- PhysicsService owns its dependencies' lifecycle.
	PhysicsIntegrator:Init({})
	BallPool:Init({})

	-- Release any in-flight ball if a player disconnects mid-shot.
	Players.PlayerRemoving:Connect(function(player: Player)
		local ball = _activeBalls[player.UserId]
		if ball then
			BallPool:Release(ball.model)
			_activeBalls[player.UserId] = nil
		end
	end)

	_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		self:OnHeartbeat(dt)
	end)
end

function PhysicsService:Update(_dt: number) end

function PhysicsService:Destroy()
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end

	-- Release all active balls before tearing down the pool.
	for _, ball in pairs(_activeBalls) do
		if ball then
			BallPool:Release(ball.model)
		end
	end
	table.clear(_activeBalls)

	BallPool:Destroy()
	PhysicsIntegrator:Destroy()
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Initiates an authoritative ball shot for a player.
-- Leases a ball from BallPool, computes launch velocity via
-- PhysicsIntegrator:ComputeInitialVelocity, and registers the ball for
-- Heartbeat-driven simulation until it lands.
--
-- One active ball per player is enforced. A second call while the first
-- ball is still in flight is silently dropped (with a warning).
--
-- clubData must contain { maxSpeed: number, loftDegrees: number, spinRPM: number }.
-- startCFrame is the ball's world position at launch (tee, lie, or drop point).
function PhysicsService:SimulateSwing(
	player: Player,
	swingIntent: Types.SwingIntent,
	clubData: { maxSpeed: number, loftDegrees: number, spinRPM: number },
	startCFrame: CFrame
)
	if _activeBalls[player.UserId] then
		warn("[PhysicsService] SimulateSwing: " .. player.Name .. " already has an active ball — ignoring")
		return
	end

	local model = BallPool:Lease()

	local velocity, spin = PhysicsIntegrator:ComputeInitialVelocity(
		{
			aimVector = swingIntent.aimVector,
			power     = swingIntent.power,
			accuracy  = swingIntent.accuracy,
		},
		clubData
	)

	local initState: BallPhysState = {
		pos  = startCFrame.Position,
		vel  = velocity,
		spin = spin,
	}

	-- Move ball to launch position before the first Heartbeat tick.
	local part = model.PrimaryPart
	if part then
		part.CFrame = startCFrame
	end

	-- Stamp ownership and state onto the BallModel so PhysicsService and
	-- clients can read them without a separate lookup table.
	local sv = model:FindFirstChild("StateValue") :: StringValue?
	if sv then sv.Value = "IN_FLIGHT" end

	local ov = model:FindFirstChild("OwnerValue") :: ObjectValue?
	if ov then ov.Value = player end

	_activeBalls[player.UserId] = {
		id         = "ball_" .. tostring(player.UserId),
		player     = player,
		model      = model,
		physState  = initState,
		trajectory = { initState.pos },
		inFlight   = true,
	} :: ActiveBall

	-- The Heartbeat loop drives the simulation from here.
end

-- Forwards a wind update from WeatherService to PhysicsIntegrator.
-- The new wind vector takes effect on the very next Step call.
function PhysicsService:SetWind(windVec: Vector3)
	PhysicsIntegrator:SetWind(windVec)
end

return PhysicsService
