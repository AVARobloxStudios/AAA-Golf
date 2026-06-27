--!strict
-- InputModeController — LocalScript thin runner (Sprint 16)
-- All logic lives in InputModeControllerModule so it can be required and
-- tested independently by Sprint16ClientTest.

local InputModeControllerModule =
	require(script.Parent.Parent.Modules.InputModeControllerModule)

InputModeControllerModule:Init()
