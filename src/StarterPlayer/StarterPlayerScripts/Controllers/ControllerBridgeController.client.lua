--!strict
-- ControllerBridgeController — LocalScript thin runner (Sprint 19)
-- All logic lives in ControllerBridgeControllerModule so it can be required
-- and tested independently by Sprint19ClientTest.

local ControllerBridgeControllerModule =
	require(script.Parent.Parent.Modules.ControllerBridgeControllerModule)

ControllerBridgeControllerModule:Init()
