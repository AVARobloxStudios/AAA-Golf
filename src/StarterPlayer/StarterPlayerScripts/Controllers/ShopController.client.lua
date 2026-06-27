--!strict
-- ShopController — LocalScript thin runner (Sprint 14)
-- All logic lives in ShopControllerModule so it can be required and tested
-- independently by Sprint14ClientTest.

local ShopControllerModule =
	require(script.Parent.Parent.Modules.ShopControllerModule)

ShopControllerModule:Init()
