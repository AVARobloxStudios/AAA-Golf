--!strict
-- RoundCompletionClientController — LocalScript thin runner (Sprint 31)
-- All logic lives in RoundCompletionClientControllerModule so it can be required
-- and tested independently by Sprint31ClientTest.

local RoundCompletionClientControllerModule =
	require(script.Parent.Parent.Modules.RoundCompletionClientControllerModule)

RoundCompletionClientControllerModule:Init()
