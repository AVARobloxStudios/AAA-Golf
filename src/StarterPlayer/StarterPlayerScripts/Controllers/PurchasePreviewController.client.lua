--!strict
-- PurchasePreviewController — LocalScript thin runner (Sprint 14)
-- All logic lives in PurchasePreviewControllerModule so it can be required
-- and tested independently by Sprint14ClientTest.

local PurchasePreviewControllerModule =
	require(script.Parent.Parent.Modules.PurchasePreviewControllerModule)

PurchasePreviewControllerModule:Init()
