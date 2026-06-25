--!strict
-- PhysicsIntegrator — Server-only ModuleScript
-- Authoritative RK4 ball-flight integrator. Forces: gravity, quadratic drag,
-- Magnus lift/curve, spin decay, ambient wind.
-- ShadowPhysicsIntegrator (client) mirrors this at 30 Hz for visual smoothness;
-- BallResolved events reconcile any drift. Never instantiated — used as singleton.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BPC = require(ReplicatedStorage.Shared.Modules.BallPhysicsConstants)

-- ── Types ──────────────────────────────────────────────────────────────────

type BallPhysState = { pos: Vector3, vel: Vector3, spin: Vector3 }

-- ── Tuning constants ───────────────────────────────────────────────────────

-- Drag: encapsulates 0.5 * ρ_air / m_ball in Roblox stud units.
-- ρ_air and m_ball are not exposed constants — adjust DRAG_SCALE during playtesting.
-- Increasing DRAG_SCALE reduces range; decreasing inflates it.
local DRAG_SCALE = 0.002
local K_DRAG     = 0.5 * BPC.DRAG_COEFF * BPC.BALL_AREA * DRAG_SCALE

-- Maximum horizontal aim deflection at |accuracy| = 1.0.
-- Positive accuracy = hook (left curve when player faces +Z); negative = slice.
local MAX_AIM_DEFLECT_RAD = math.rad(20)

-- Fraction of backspin rate applied as sidespin at |accuracy| = 1.0.
-- Controls how much the ball curves in flight vs. off the tee.
local SIDESPIN_FACTOR = 0.5

-- BPC.SPIN_DECAY is a per-step multiplier calibrated at 60 Hz.
-- Convert to a continuous per-second rate so decay is identical at any step
-- frequency (server 60 Hz and ShadowPhysicsIntegrator 30 Hz stay in sync).
local SPIN_DECAY_HZ      = 60
local SPIN_DECAY_PER_SEC = math.log(BPC.SPIN_DECAY) * SPIN_DECAY_HZ  -- negative; ≈ −0.120 /s

-- ── Module state ───────────────────────────────────────────────────────────

-- Wind acceleration in studs/s², updated by PhysicsService when WeatherService changes.
local _wind: Vector3 = Vector3.zero

-- ── Module ─────────────────────────────────────────────────────────────────

local PhysicsIntegrator = {}
PhysicsIntegrator.__index = PhysicsIntegrator

function PhysicsIntegrator:Init(dependencies: { [string]: any })
	if dependencies and dependencies.wind then
		_wind = dependencies.wind :: Vector3
	end
end

function PhysicsIntegrator:Update(_dt: number) end

function PhysicsIntegrator:Destroy()
	_wind = Vector3.zero
end

-- Called by PhysicsService each time WeatherService updates the wind state.
-- windVec is a pre-scaled acceleration in studs/s².
function PhysicsIntegrator:SetWind(windVec: Vector3)
	_wind = windVec
end

-- ── RK4 state helpers ──────────────────────────────────────────────────────

-- Computes the time derivative of a BallPhysState.
-- Spin derivative is zero here — decay is applied multiplicatively after each Step.
function PhysicsIntegrator:_deriv(state: BallPhysState): BallPhysState
	local vel  = state.vel
	local spin = state.spin
	local speed = vel.Magnitude

	-- Quadratic drag: F/m = −K · |v| · v  (direction opposes velocity).
	local a_drag = vel * (-K_DRAG * speed)

	-- Magnus force: a spinning ball deflects perpendicular to both spin axis and velocity.
	-- For backspin (spin axis = −rightOfAim), this produces upward lift.
	-- For sidespin (spin axis = ±Y), this produces hook or slice curve.
	local a_magnus = spin:Cross(vel) * BPC.MAGNUS_COEFF

	local a_total = Vector3.new(0, BPC.GRAVITY, 0) + a_drag + a_magnus + _wind

	return { pos = vel, vel = a_total, spin = Vector3.zero }
end

-- Adds two states component-wise (used to build RK4 mid-point states).
function PhysicsIntegrator:_add(a: BallPhysState, b: BallPhysState): BallPhysState
	return {
		pos  = a.pos  + b.pos,
		vel  = a.vel  + b.vel,
		spin = a.spin + b.spin,
	}
end

-- Scales all components of a state by scalar k.
function PhysicsIntegrator:_scale(state: BallPhysState, k: number): BallPhysState
	return {
		pos  = state.pos  * k,
		vel  = state.vel  * k,
		spin = state.spin * k,
	}
end

-- Computes the RK4 weighted combination: (k1 + 2·k2 + 2·k3 + k4) / 6.
function PhysicsIntegrator:_weightedSum(
	k1: BallPhysState, k2: BallPhysState,
	k3: BallPhysState, k4: BallPhysState
): BallPhysState
	return {
		pos  = (k1.pos  + k2.pos  * 2 + k3.pos  * 2 + k4.pos)  / 6,
		vel  = (k1.vel  + k2.vel  * 2 + k3.vel  * 2 + k4.vel)  / 6,
		spin = (k1.spin + k2.spin * 2 + k3.spin * 2 + k4.spin) / 6,
	}
end

-- Returns true when the ball centre has reached or passed the ground plane and
-- is travelling downward. PhysicsService uses this as a cue to raycast for the
-- actual landing surface and apply surface-specific bounce/roll.
function PhysicsIntegrator:CheckLanding(state: BallPhysState): boolean
	return state.pos.Y <= BPC.BALL_RADIUS and state.vel.Y < 0
end

-- Backwards-compatible alias for any code referencing the old private name.
PhysicsIntegrator._checkLanding = PhysicsIntegrator.CheckLanding

-- ── Public API ─────────────────────────────────────────────────────────────

-- Advances ball state by `dt` seconds using 4th-order Runge-Kutta.
-- Assumes constant forces over dt (reasonable for dt ≤ 1/30 s).
-- Spin decay is applied as a dt-scaled exponential after the integration step;
-- the continuous rate is derived from BPC.SPIN_DECAY calibrated at SPIN_DECAY_HZ.
-- Terrain collision is intentionally not handled here — PhysicsService
-- raycasts against the actual course geometry after each call to Step.
function PhysicsIntegrator:Step(state: BallPhysState, dt: number): BallPhysState
	local k1 = self:_deriv(state)
	local k2 = self:_deriv(self:_add(state, self:_scale(k1, dt * 0.5)))
	local k3 = self:_deriv(self:_add(state, self:_scale(k2, dt * 0.5)))
	local k4 = self:_deriv(self:_add(state, self:_scale(k3, dt)))

	local d = self:_weightedSum(k1, k2, k3, k4)

	local newState: BallPhysState = {
		pos  = state.pos + d.pos * dt,
		vel  = state.vel + d.vel * dt,
		spin = state.spin * math.exp(SPIN_DECAY_PER_SEC * dt),  -- dt-consistent exponential decay
	}

	return newState
end

-- Converts a SwingIntent + club data into an initial velocity and spin Vector3 pair.
-- Caller constructs BallPhysState as: { pos = ballWorldPos, vel = vel, spin = spin }.
--
-- Accuracy convention (for a player facing +Z):
--   accuracy =  1.0 → hook  (ball curves left,  aim deflected left,  −Y sidespin)
--   accuracy = -1.0 → slice (ball curves right, aim deflected right, +Y sidespin)
--   accuracy =  0.0 → straight (backspin only from loft, no lateral curve)
function PhysicsIntegrator:ComputeInitialVelocity(
	intent: { aimVector: Vector3, power: number, accuracy: number },
	clubData: { maxSpeed: number, loftDegrees: number, spinRPM: number }
): (Vector3, Vector3)
	local speed   = clubData.maxSpeed * intent.power
	local loftRad = math.rad(clubData.loftDegrees)

	-- Flatten aim into the XZ plane and guard against a near-zero projection
	-- (e.g. aimVector pointing straight up). Vector3.new(0,0,0).Unit is NaN in Roblox.
	local aimXZ_raw = Vector3.new(intent.aimVector.x, 0, intent.aimVector.z)
	if aimXZ_raw.Magnitude < 0.001 then
		warn("[PhysicsIntegrator] ComputeInitialVelocity: aimVector has near-zero XZ component; defaulting to +Z")
		aimXZ_raw = Vector3.new(0, 0, 1)
	end
	local aimXZ = aimXZ_raw.Unit

	-- Accuracy yaws the horizontal aim: positive = CCW from above = left when facing +Z.
	local yawCF  = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), intent.accuracy * MAX_AIM_DEFLECT_RAD)
	local deflAim = (yawCF * aimXZ).Unit

	-- Right-hand perpendicular to the POST-yaw (deflected) aim in the XZ plane.
	-- Must be derived from deflAim, not aimXZ: pitching deflAim around aimXZ's right
	-- axis introduces a spurious lateral component when accuracy ≠ 0, because the
	-- two vectors are not perpendicular after the yaw.
	local rightOfDeflAim = Vector3.new(deflAim.z, 0, -deflAim.x)

	-- Loft pitches deflAim upward around the post-yaw right axis (pure upward tilt).
	local pitchCF   = CFrame.fromAxisAngle(-rightOfDeflAim, loftRad)
	local launchDir = (pitchCF * deflAim).Unit

	local velocity = launchDir * speed

	-- Backspin axis is −rightOfDeflAim so that spin:Cross(vel) produces upward lift.
	-- Using the post-yaw axis keeps backspin aligned with the actual flight direction.
	local spinRad       = (clubData.spinRPM / 60) * (2 * math.pi)  -- convert RPM → rad/s
	local backspinOmega = -rightOfDeflAim * spinRad

	-- Sidespin around the world Y-axis. Negative Y → hook (left Magnus deflection).
	-- At accuracy = 0 this is zero; curve is driven purely by backspin asymmetry.
	local sidespinOmega = Vector3.new(0, -intent.accuracy * spinRad * SIDESPIN_FACTOR, 0)

	local spin = backspinOmega + sidespinOmega

	return velocity, spin
end

return PhysicsIntegrator
