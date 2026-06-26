--!strict
-- HUDController — LocalScript thin runner (Sprint 9)
-- All logic lives in HUDControllerModule so it can be required and tested
-- independently by Sprint9ClientTest.

local HUDControllerModule =
	require(script.Parent.Parent.Modules.HUDControllerModule)

HUDControllerModule:Init()
