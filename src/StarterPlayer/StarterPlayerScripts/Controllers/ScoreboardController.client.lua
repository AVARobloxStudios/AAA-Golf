--!strict
-- ScoreboardController — LocalScript thin runner (Sprint 12)
-- All logic lives in ScoreboardControllerModule so it can be required and
-- tested independently by Sprint12ClientTest.

local ScoreboardControllerModule =
	require(script.Parent.Parent.Modules.ScoreboardControllerModule)

ScoreboardControllerModule:Init()
