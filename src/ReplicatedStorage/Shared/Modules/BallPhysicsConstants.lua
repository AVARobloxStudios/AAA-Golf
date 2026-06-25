-- BallPhysicsConstants — Physics simulation parameters
-- Tunable values for ball flight, bounce, and roll
-- Read by server (authoritative) and client (shadow physics)

local BallPhysicsConstants = {}

-- Core physics
BallPhysicsConstants.GRAVITY = -196         -- studs/s² (arcade feel; real=-32.7)
BallPhysicsConstants.BALL_RADIUS = 0.21     -- studs (matches SphereShape default)
BallPhysicsConstants.DRAG_COEFF = 0.47      -- sphere Cd
BallPhysicsConstants.BALL_AREA = 0.139      -- studs² (π * r²)
BallPhysicsConstants.MAGNUS_COEFF = 0.00015 -- cross-product Magnus force coefficient
BallPhysicsConstants.SPIN_DECAY = 0.998     -- spin multiplier per integration step

-- Bounce restitution per surface (fraction of incoming speed retained)
BallPhysicsConstants.BOUNCE_RESTITUTION = {
	FAIRWAY = 0.45,
	GREEN = 0.25,
	SAND = 0.10,
	WATER = 0.00,
	OOB = 0.00,
	ROUGH = 0.35,
}

-- Roll friction per surface (speed fraction retained per step after landing)
BallPhysicsConstants.ROLL_FRICTION = {
	FAIRWAY = 0.92,
	GREEN = 0.96,
	SAND = 0.70,
	ROUGH = 0.85,
}

-- Surface-specific behaviour
BallPhysicsConstants.SAND_SINK_DEPTH = 0.15     -- studs ball sinks into sand
BallPhysicsConstants.WATER_PENALTY_DISTANCE = 1  -- studs back from entry point

return BallPhysicsConstants
