--!strict
-- AckBridgeController — LocalScript thin runner (Sprint 22)
-- All logic lives in AckBridgeControllerModule so it can be required and
-- tested independently by Sprint22ClientTest.

local AckBridgeControllerModule =
	require(script.Parent.Parent.Modules.AckBridgeControllerModule)

AckBridgeControllerModule:Init()
