--!strict
-- RequestHistoryController — LocalScript thin runner (Sprint 22)
-- All logic lives in RequestHistoryControllerModule so it can be required and
-- tested independently by Sprint22ClientTest.

local RequestHistoryControllerModule =
	require(script.Parent.Parent.Modules.RequestHistoryControllerModule)

RequestHistoryControllerModule:Init()
