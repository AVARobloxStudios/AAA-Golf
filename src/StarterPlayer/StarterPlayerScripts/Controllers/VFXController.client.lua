--!strict
-- VFXController — LocalScript thin runner (Sprint 17)
-- All logic lives in VFXControllerModule so it can be required and tested
-- independently by Sprint17ClientTest.

local VFXControllerModule =
	require(script.Parent.Parent.Modules.VFXControllerModule)

VFXControllerModule:Init()
