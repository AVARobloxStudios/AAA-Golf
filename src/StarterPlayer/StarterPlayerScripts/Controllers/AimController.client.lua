--!strict
-- AimController — LocalScript thin runner (Sprint 11)
-- All logic lives in AimControllerModule so it can be required and tested
-- independently by Sprint11ClientTest.

local AimControllerModule =
	require(script.Parent.Parent.Modules.AimControllerModule)

AimControllerModule:Init()
