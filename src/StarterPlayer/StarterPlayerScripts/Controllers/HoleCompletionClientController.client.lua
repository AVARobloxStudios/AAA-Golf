--!strict
-- HoleCompletionClientController — LocalScript thin runner (Sprint 30)
-- All logic lives in HoleCompletionClientControllerModule so it can be required
-- and tested independently by Sprint30ClientTest.

local HoleCompletionClientControllerModule =
	require(script.Parent.Parent.Modules.HoleCompletionClientControllerModule)

HoleCompletionClientControllerModule:Init()
