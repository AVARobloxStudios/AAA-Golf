--!strict
-- ShopActionBridgeController — LocalScript thin runner (Sprint 21)
-- All logic lives in ShopActionBridgeControllerModule so it can be required
-- and tested independently by Sprint21ClientTest.

local ShopActionBridgeControllerModule =
	require(script.Parent.Parent.Modules.ShopActionBridgeControllerModule)

ShopActionBridgeControllerModule:Init()
