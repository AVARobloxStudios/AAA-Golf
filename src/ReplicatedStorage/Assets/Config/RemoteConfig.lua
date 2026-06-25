-- RemoteConfig — Live-tunable server constants fetched at session start
-- Managed by ConfigService.server; stub for Sprint 0

local RemoteConfig = {}

-- Default values (overridden by ConfigService live fetch in production)
RemoteConfig.Defaults = {
	MAX_SWING_POWER_OVERRIDE = 1.0,
	COIN_MULTIPLIER = 1.0,
	XP_MULTIPLIER = 1.0,
	PHYSICS_TICK_RATE = 60,
}

return RemoteConfig
