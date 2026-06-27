--!strict
-- GameplayActionBridgeController — LocalScript thin runner (Sprint 21)
-- All logic lives in GameplayActionBridgeControllerModule so it can be
-- required and tested independently by Sprint21ClientTest.

local GameplayActionBridgeControllerModule =
	require(script.Parent.Parent.Modules.GameplayActionBridgeControllerModule)

GameplayActionBridgeControllerModule:Init()
