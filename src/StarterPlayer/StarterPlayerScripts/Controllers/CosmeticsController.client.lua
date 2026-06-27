--!strict
-- CosmeticsController — LocalScript thin runner (Sprint 13)
-- All logic lives in CosmeticsControllerModule so it can be required and
-- tested independently by Sprint13ClientTest.

local CosmeticsControllerModule =
	require(script.Parent.Parent.Modules.CosmeticsControllerModule)

CosmeticsControllerModule:Init()
