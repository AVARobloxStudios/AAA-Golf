--!strict
-- LoadingController — LocalScript thin runner (Sprint 10)
-- All logic lives in LoadingControllerModule so it can be required and tested
-- independently by Sprint10ClientTest.

local LoadingControllerModule =
	require(script.Parent.Parent.Modules.LoadingControllerModule)

LoadingControllerModule:Init()
