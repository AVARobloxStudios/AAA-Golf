-- FeatureFlags — Boolean gates for incremental feature rollout
-- Managed by ConfigService.server; stub for Sprint 0

local FeatureFlags = {}

FeatureFlags.Flags = {
	ENABLE_SHOP             = false,  -- Phase 2
	ENABLE_BATTLE_PASS      = false,  -- Phase 4
	ENABLE_TOURNAMENTS      = false,  -- Phase 5
	ENABLE_FRIENDS_PANEL    = false,  -- Phase 2
	ENABLE_MATCHMAKING      = false,  -- Phase 2
	ENABLE_QUESTS           = false,  -- M4 Alpha Prep
	ENABLE_DAILY_REWARDS    = false,  -- M4 Alpha Prep
	ENABLE_AVATAR_CUSTOMISER = false, -- Phase 2
}

return FeatureFlags
