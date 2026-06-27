--!strict
-- LeaderboardController — LocalScript thin runner (Sprint 12)
-- All logic lives in LeaderboardControllerModule so it can be required and
-- tested independently by Sprint12ClientTest.

local LeaderboardControllerModule =
	require(script.Parent.Parent.Modules.LeaderboardControllerModule)

LeaderboardControllerModule:Init()
