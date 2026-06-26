--!strict
-- PauseController — LocalScript thin runner (Sprint 10)
-- All logic lives in PauseControllerModule so it can be required and tested
-- independently by Sprint10ClientTest.

local PauseControllerModule =
	require(script.Parent.Parent.Modules.PauseControllerModule)

PauseControllerModule:Init()
