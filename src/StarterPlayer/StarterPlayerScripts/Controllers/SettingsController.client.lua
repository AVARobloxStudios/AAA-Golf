--!strict
-- SettingsController — LocalScript thin runner (Sprint 10)
-- All logic lives in SettingsControllerModule so it can be required and tested
-- independently by Sprint10ClientTest.

local SettingsControllerModule =
	require(script.Parent.Parent.Modules.SettingsControllerModule)

SettingsControllerModule:Init()
