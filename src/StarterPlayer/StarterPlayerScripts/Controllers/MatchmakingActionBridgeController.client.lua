--!strict
-- MatchmakingActionBridgeController — LocalScript thin runner (Sprint 21)
-- All logic lives in MatchmakingActionBridgeControllerModule so it can be
-- required and tested independently by Sprint21ClientTest.

local MatchmakingActionBridgeControllerModule =
	require(script.Parent.Parent.Modules.MatchmakingActionBridgeControllerModule)

MatchmakingActionBridgeControllerModule:Init()
