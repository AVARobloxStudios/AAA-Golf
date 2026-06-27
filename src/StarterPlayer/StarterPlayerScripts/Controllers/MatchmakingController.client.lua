--!strict
-- MatchmakingController — LocalScript thin runner (Sprint 15)
-- All logic lives in MatchmakingControllerModule so it can be required and
-- tested independently by Sprint15ClientTest.

local MatchmakingControllerModule =
	require(script.Parent.Parent.Modules.MatchmakingControllerModule)

MatchmakingControllerModule:Init()
