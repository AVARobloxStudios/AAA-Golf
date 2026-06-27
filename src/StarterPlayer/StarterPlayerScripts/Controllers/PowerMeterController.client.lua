--!strict
-- PowerMeterController — LocalScript thin runner (Sprint 11)
-- All logic lives in PowerMeterControllerModule so it can be required and
-- tested independently by Sprint11ClientTest.

local PowerMeterControllerModule =
	require(script.Parent.Parent.Modules.PowerMeterControllerModule)

PowerMeterControllerModule:Init()
