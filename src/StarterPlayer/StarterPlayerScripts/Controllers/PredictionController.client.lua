--!strict
-- PredictionController — LocalScript thin runner (Sprint 7)
-- All logic lives in PredictionControllerModule so it can be required and tested
-- independently by Sprint7ClientTest.

local PredictionControllerModule =
	require(script.Parent.Parent.Modules.PredictionControllerModule)

PredictionControllerModule:Init()
