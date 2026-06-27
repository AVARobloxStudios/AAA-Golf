--!strict
-- InventoryController — LocalScript thin runner (Sprint 13)
-- All logic lives in InventoryControllerModule so it can be required and
-- tested independently by Sprint13ClientTest.

local InventoryControllerModule =
	require(script.Parent.Parent.Modules.InventoryControllerModule)

InventoryControllerModule:Init()
