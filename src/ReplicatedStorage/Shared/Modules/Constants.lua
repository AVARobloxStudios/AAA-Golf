-- Constants — Global scalar constants shared by server and client

local Constants = {}

-- Physics
Constants.GRAVITY = -196
Constants.BALL_RADIUS = 0.21
Constants.STUD_TO_YARD = 0.333

-- Networking
Constants.BALL_POSITION_BROADCAST_HZ = 60
Constants.SCOREBOARD_BROADCAST_INTERVAL = 2
Constants.PROFILE_HEARTBEAT_INTERVAL = 60
Constants.REMOTEFUNCTION_TIMEOUT = 10

-- Anti-cheat
Constants.TRUST_SCORE_DEFAULT = 80
Constants.TRUST_SCORE_KICK_THRESHOLD = 20
Constants.SWING_INTENT_RATE_LIMIT = 3      -- seconds between allowed swings
Constants.EVENT_RATE_LIMIT_WINDOW = 10     -- seconds
Constants.EVENT_RATE_LIMIT_MAX = 20        -- max events per window

-- Session
Constants.SESSION_LOCK_DEFER_SECONDS = 30
Constants.SESSION_LOCK_MAX_RETRIES = 1

-- Camera
Constants.FOLLOW_BALL_LERP_ALPHA = 0.08
Constants.FOLLOW_BALL_LEAD_TIME = 0.3      -- seconds
Constants.APEX_HOLD_DURATION = 0.2        -- seconds
Constants.BALL_SETTLED_VELOCITY_THRESHOLD = 0.5

-- Aim assist
Constants.AIM_ASSIST_DURATION = 3.0        -- seconds, Course 1 only

-- LOD thresholds (studs)
Constants.LOD_FULL_DISTANCE = 80
Constants.LOD_REDUCED_DISTANCE = 200
Constants.LOD_TICK_INTERVAL = 2            -- seconds between LOD updates

-- Ball pool
Constants.BALL_POOL_SIZE = 10

-- VFX
Constants.VFX_POOL_SIZE = 8
Constants.MAX_ACTIVE_PARTICLES = 500

-- Economy
Constants.XP_ROUND_MIN = 50
Constants.XP_ROUND_MAX = 200

return Constants
