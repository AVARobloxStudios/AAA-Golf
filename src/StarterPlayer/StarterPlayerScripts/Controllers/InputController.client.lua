--!strict
-- InputController — LocalScript thin runner (Sprint 6)
-- All logic lives in InputControllerModule so it can be required and tested
-- independently by Sprint6ClientTest.

local InputControllerModule =
	require(script.Parent.Parent.Modules.InputControllerModule)

InputControllerModule:Init()
