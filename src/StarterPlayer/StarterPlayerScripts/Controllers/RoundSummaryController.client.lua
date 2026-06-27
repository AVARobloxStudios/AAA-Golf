--!strict
-- RoundSummaryController — LocalScript thin runner (Sprint 12)
-- All logic lives in RoundSummaryControllerModule so it can be required and
-- tested independently by Sprint12ClientTest.

local RoundSummaryControllerModule =
	require(script.Parent.Parent.Modules.RoundSummaryControllerModule)

RoundSummaryControllerModule:Init()
