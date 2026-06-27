--!strict
-- GameBusBridgeController — LocalScript thin runner (Sprint 19)
-- All logic lives in GameBusBridgeControllerModule so it can be required and
-- tested independently by Sprint19ClientTest.

local GameBusBridgeControllerModule =
	require(script.Parent.Parent.Modules.GameBusBridgeControllerModule)

GameBusBridgeControllerModule:Init()
