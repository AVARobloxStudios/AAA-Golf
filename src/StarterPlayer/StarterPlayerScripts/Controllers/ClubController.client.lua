--!strict
-- ClubController — LocalScript thin runner (Sprint 11)
-- ClubControllerModule is a legacy state container (no Z/X binding, no gameplay
-- integration).  The playable hole uses ClubManager via PlayableHoleControllerModule.
-- Init() is intentionally NOT called here.  The module is required only so Roblox
-- caches it; Sprint11ClientTest drives Init() itself in its test setup.

local _ = require(script.Parent.Parent.Modules.ClubControllerModule)
