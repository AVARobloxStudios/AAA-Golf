--!strict
-- ScoreRevealClientController — LocalScript thin runner (Sprint 29)
-- All logic lives in ScoreRevealClientControllerModule so it can be required
-- and tested independently by Sprint29ClientTest.

local ScoreRevealClientControllerModule =
	require(script.Parent.Parent.Modules.ScoreRevealClientControllerModule)

ScoreRevealClientControllerModule:Init()
