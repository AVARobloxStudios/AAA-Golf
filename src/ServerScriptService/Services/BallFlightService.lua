--!strict
-- BallFlightService — Server, Sprint A
-- Kinematic ball-flight simulation. The ball Part stays Anchored=true; its CFrame
-- is driven via RunService.Heartbeat each frame. All state is owned here.
--
-- Physics pipeline per tick:
--   InFlight / Bouncing  : gravity + quadratic drag + backspin lift + sidespin Magnus
--   Rolling              : constant friction deceleration along ground surface
--   Stopped              : fires onStopped callback, disconnects its own Heartbeat
--
-- Public API
--   Launch(ball, direction, power, spinData, callbacks)
--   AbortBall(ball)
--   GetPhase(ball) → FlightPhase?

local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Debris     = game:GetService("Debris")

-- ─── Tuning Constants ─────────────────────────────────────────────────────────

local GravityScale        = 1.00    -- multiplied against workspace.Gravity (196 studs/s²)
local DragCoefficient     = 0.00008 -- quadratic air drag: decel = Cd · |v|² (studs⁻¹)
local LiftCoefficient     = 0.018   -- backspin lift (was 0.012; more pronounced high-spin trajectory)
local SidespinCoefficient = 0.12    -- Magnus: side accel = Cs · v_h · sideSpin (s⁻¹)
local BounceCoefficient   = 0.28    -- energy retained per bounce (was 0.38; balls die faster — wedges stick)
local RollFriction        = 0.38    -- rolling resistance coefficient (was 0.30; stops sooner)
local MaxCarryDistance    = 450     -- studs; hard abort if ball travels this far horizontally
local MaxRollDistance     = 150     -- studs; hard stop when roll distance from landing exceeds this

local DriverLoftDeg    = 10.5   -- degrees above horizontal (was 11.0; slightly flatter/faster driver)
local PutterLoftDeg    = 2.0    -- degrees above horizontal for putter shots
local LaunchSpeedScale = 3.50   -- design-unit power → studs/s (was 3.20; more punch across all clubs)

-- ─── Wind (Milestone 4 placeholder) ──────────────────────────────────────────
-- WindAcceleration is a constant acceleration vector added each flight tick.
-- Default = zero (no wind). Set to e.g. Vector3.new(2, 0, 0) for a 2 studs/s² east breeze.
-- A later milestone can expose this per-hole via a service method.
local WindAcceleration: Vector3 = Vector3.zero

-- ─── Simulation Constants ─────────────────────────────────────────────────────

local BALL_RADIUS      = 0.275  -- studs (half of 0.55 diameter, updated Milestone 1.95)
local STOP_THRESHOLD   = 0.8    -- studs/s; ball is "stopped" below this
local ROLL_ENTER_SPEED = 12.0   -- studs/s; landing speed below which ball rolls instead of bounces
local MAX_BOUNCES      = 5      -- after this many bounces, force rolling regardless of speed
local GROUND_CHECK_Y   = -30    -- studs; abort if ball falls below this world Y

-- ─── Types ────────────────────────────────────────────────────────────────────

export type FlightPhase = "InFlight" | "Bouncing" | "Rolling" | "Stopped"

type SpinData = {
	backSpin:     number,   -- 0..1
	sideSpin:     number,   -- -1..1  (-=draw curve, +=fade curve)
	isPutt:       boolean?, -- true when using putter (low loft, no trail)
	loftDeg:      number?,  -- per-club loft override in degrees; nil → use DriverLoftDeg
	rollFricScale: number?, -- multiplier on RollFriction (Driver=0.52, Wedge=2.1); nil → 1.0
}

type Callbacks = {
	onStateChange: ((phase: FlightPhase) -> ())?,
	onStopped:     ((finalPos: Vector3)  -> ())?,
}

type Session = {
	ball:       Part,
	pos:        Vector3,
	vel:        Vector3,
	spin:       SpinData,
	phase:      FlightPhase,
	bounces:    number,
	launchPos:  Vector3,
	landPos:    Vector3?,
	conn:       RBXScriptConnection?,
	cb:         Callbacks,
}

-- ─── Module ───────────────────────────────────────────────────────────────────

local BallFlightService = {}

local _sessions: { [Part]: Session } = {}
local _gravity:  number = 196.2   -- updated from workspace.Gravity on each Launch

-- ─── Ground Detection ─────────────────────────────────────────────────────────

local function _raycast(pos: Vector3, ball: Part): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ball }

	local origin = pos + Vector3.new(0, BALL_RADIUS + 0.05, 0)
	local dir    = Vector3.new(0, -(BALL_RADIUS * 2.5), 0)
	return workspace:Raycast(origin, dir, params)
end

-- ─── FX ───────────────────────────────────────────────────────────────────────

local function _enableTrail(ball: Part, on: boolean)
	local trail = ball:FindFirstChild("BallTrail")
	if trail and trail:IsA("Trail") then
		(trail :: Trail).Enabled = on
	end
end

-- Server-side landing puff (first ground contact).
-- Client handles the launch-side particles via the ShotFired GameBus event.
local function _emitLandingPuff(ball: Part)
	local emitter         = Instance.new("ParticleEmitter")
	emitter.Rate          = 0
	emitter.Speed         = NumberRange.new(3, 10)
	emitter.Lifetime      = NumberRange.new(0.25, 0.55)
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color         = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 210, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	emitter.LightEmission = 0.05
	emitter.Parent        = ball
	emitter:Emit(12)
	Debris:AddItem(emitter, 2)
end

-- Smaller puff for each subsequent bounce.
local function _emitBouncePuff(ball: Part)
	local emitter         = Instance.new("ParticleEmitter")
	emitter.Rate          = 0
	emitter.Speed         = NumberRange.new(2, 6)
	emitter.Lifetime      = NumberRange.new(0.15, 0.35)
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color         = ColorSequence.new(Color3.fromRGB(190, 185, 170))
	emitter.LightEmission = 0
	emitter.Parent        = ball
	emitter:Emit(6)
	Debris:AddItem(emitter, 1)
end

-- ─── Session Lifecycle ────────────────────────────────────────────────────────

local function _stop(session: Session)
	if session.conn then
		session.conn:Disconnect()
		session.conn = nil
	end
	session.phase = "Stopped"
	_enableTrail(session.ball, false)
	_sessions[session.ball] = nil

	if session.cb.onStateChange then
		session.cb.onStateChange("Stopped")
	end
	if session.cb.onStopped then
		session.cb.onStopped(session.pos)
	end
end

local function _enterRolling(session: Session, flatVel: Vector3)
	session.phase = "Rolling"
	session.vel   = flatVel
	_enableTrail(session.ball, false)
	if session.cb.onStateChange then
		session.cb.onStateChange("Rolling")
	end
end

local function _applyBounce(session: Session, hitNormal: Vector3, hitPos: Vector3)
	local v = session.vel

	-- Decompose into normal (perpendicular to surface) and tangential (parallel)
	local vNorm = v:Dot(hitNormal) * hitNormal
	local vTan  = v - vNorm

	-- Reflect normal, apply restitution; slight tangential friction
	local newV  = -vNorm * BounceCoefficient + vTan * 0.88

	session.pos     = hitPos + hitNormal * BALL_RADIUS
	session.bounces += 1

	if session.landPos == nil then
		session.landPos = session.pos
		_enableTrail(session.ball, false)   -- trail off at first ground contact
		_emitLandingPuff(session.ball)
	else
		_emitBouncePuff(session.ball)
	end

	local hSpeed = Vector3.new(newV.X, 0, newV.Z).Magnitude
	if hSpeed < ROLL_ENTER_SPEED or session.bounces >= MAX_BOUNCES then
		_enterRolling(session, Vector3.new(newV.X, 0, newV.Z))
	else
		session.vel   = newV
		session.phase = "Bouncing"
		if session.cb.onStateChange then
			session.cb.onStateChange("Bouncing")
		end
	end
end

-- ─── Physics Ticks ────────────────────────────────────────────────────────────

local function _tickFlight(session: Session, dt: number)
	local v     = session.vel
	local speed = v.Magnitude
	if speed < 0.001 then return end

	-- Gravity
	local gravAccel   = Vector3.new(0, -_gravity, 0)

	-- Quadratic drag (opposes velocity direction)
	local dragAccel   = -v.Unit * (speed * speed * DragCoefficient)

	-- Backspin lift (upward; magnitude proportional to horizontal speed)
	local hVel        = Vector3.new(v.X, 0, v.Z)
	local hSpeed      = hVel.Magnitude
	local liftAccel   = Vector3.new(0, hSpeed * LiftCoefficient * session.spin.backSpin, 0)

	-- Sidespin Magnus force (perpendicular to horizontal velocity, curves the ball)
	local sideAccel   = Vector3.zero
	if hSpeed > 0.01 then
		local hDir    = hVel / hSpeed
		local perpDir = Vector3.new(-hDir.Z, 0, hDir.X)   -- 90° rotation in the XZ plane
		sideAccel     = perpDir * (hSpeed * SidespinCoefficient * session.spin.sideSpin)
	end

	session.vel = v + (gravAccel + dragAccel + liftAccel + sideAccel + WindAcceleration) * dt
	session.pos = session.pos + session.vel * dt

	-- Hard carry-distance abort
	local hDist = (Vector3.new(session.pos.X, 0, session.pos.Z)
	             - Vector3.new(session.launchPos.X, 0, session.launchPos.Z)).Magnitude
	if hDist > MaxCarryDistance or session.pos.Y < GROUND_CHECK_Y then
		_stop(session)
		return
	end

	session.ball.CFrame = CFrame.new(session.pos)

	-- Ground detection (only when moving downward or near apex)
	if session.vel.Y < 3.0 then
		local hit = _raycast(session.pos, session.ball)
		if hit then
			_applyBounce(session, hit.Normal, hit.Position)
		end
	end
end

local function _tickRolling(session: Session, dt: number)
	local v     = session.vel
	local speed = v.Magnitude

	if speed < STOP_THRESHOLD then
		_stop(session)
		return
	end

	-- Roll-distance abort
	if session.landPos then
		local rolled = (Vector3.new(session.pos.X, 0, session.pos.Z)
		              - Vector3.new(session.landPos.X, 0, session.landPos.Z)).Magnitude
		if rolled >= MaxRollDistance then
			_stop(session)
			return
		end
	end

	-- Constant deceleration from rolling resistance (F = μ · m · g)
	-- rollFricScale is set per-club (Driver=0.52 rolls far; Wedge=2.1 stops fast) and
	-- multiplied by the lie rollMult (Bunker=2.20 kills roll on sand).
	local rollScale     = session.spin.rollFricScale or 1.0
	local frictionDecel = RollFriction * rollScale * _gravity
	local newSpeed      = math.max(speed - frictionDecel * dt, 0)
	session.vel         = (v / speed) * newSpeed

	session.pos = session.pos + session.vel * dt

	-- Snap to terrain surface
	local hit = _raycast(session.pos + Vector3.new(0, 0.5, 0), session.ball)
	if hit then
		session.pos = hit.Position + Vector3.new(0, BALL_RADIUS, 0)
	else
		-- No ground under the ball — let it fall briefly, re-enter InFlight
		session.vel   = session.vel + Vector3.new(0, -_gravity * dt, 0)
		session.phase = "InFlight"
	end

	session.ball.CFrame = CFrame.new(session.pos)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Launches ball using kinematic simulation. ball.Anchored must already be true.
--- direction : horizontal aim unit vector (shotShape deflection already applied by caller).
--- power     : processed design-unit power (0–125 range; same scale as SwingAnalyzer).
--- spin      : backSpin 0..1, sideSpin -1..1 (negative = draw curve, positive = fade).
--- callbacks : optional phase-change and stopped handlers.
function BallFlightService:Launch(
	ball:      Part,
	direction: Vector3,
	power:     number,
	spin:      SpinData,
	callbacks: Callbacks
)
	BallFlightService:AbortBall(ball)

	_gravity = workspace.Gravity * GravityScale

	-- Flatten direction to horizontal, apply driver loft
	local hDir = Vector3.new(direction.X, 0, direction.Z)
	if hDir.Magnitude < 0.01 then hDir = Vector3.new(0, 0, -1) end
	hDir = hDir.Unit

	local loftDeg = if spin.isPutt then PutterLoftDeg
	               elseif spin.loftDeg and spin.loftDeg > 0 then spin.loftDeg
	               else DriverLoftDeg
	local loftRad = math.rad(loftDeg)
	local loftDir = (hDir * math.cos(loftRad) + Vector3.new(0, 1, 0) * math.sin(loftRad)).Unit
	local speed   = power * LaunchSpeedScale

	local session: Session = {
		ball      = ball,
		pos       = ball.CFrame.Position,
		vel       = loftDir * speed,
		spin      = { backSpin = math.clamp(spin.backSpin, 0, 1),
		              sideSpin = math.clamp(spin.sideSpin, -1, 1) },
		phase     = "InFlight",
		bounces   = 0,
		launchPos = ball.CFrame.Position,
		landPos   = nil,
		conn      = nil,
		cb        = callbacks,
	}

	ball.Anchored                = true
	ball.AssemblyLinearVelocity  = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero

	_sessions[ball] = session

	-- Short delay so the trail doesn't streak backwards from the tee at frame 0
	if not spin.isPutt then
		task.delay(0.06, function()
			if _sessions[ball] then
				_enableTrail(ball, true)
			end
		end)
	end

	local conn = RunService.Heartbeat:Connect(function(dt: number)
		local s = _sessions[ball]
		if not s or not ball.Parent then
			BallFlightService:AbortBall(ball)
			return
		end
		if s.phase == "InFlight" or s.phase == "Bouncing" then
			_tickFlight(s, dt)
		elseif s.phase == "Rolling" then
			_tickRolling(s, dt)
		end
	end)

	session.conn = conn
end

--- Cancels the session for ball without firing callbacks.
function BallFlightService:AbortBall(ball: Part)
	local s = _sessions[ball]
	if s then
		if s.conn then s.conn:Disconnect() end
		_enableTrail(ball, false)
		_sessions[ball] = nil
	end
end

--- Returns the current flight phase for ball, or nil if no active session.
function BallFlightService:GetPhase(ball: Part): FlightPhase?
	local s = _sessions[ball]
	return if s then s.phase else nil
end

return BallFlightService
