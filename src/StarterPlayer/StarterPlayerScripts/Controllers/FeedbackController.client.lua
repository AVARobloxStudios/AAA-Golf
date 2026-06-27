--!strict
-- FeedbackController — LocalScript thin runner (Sprint 17)
-- All logic lives in FeedbackControllerModule so it can be required and
-- tested independently by Sprint17ClientTest.

local FeedbackControllerModule =
	require(script.Parent.Parent.Modules.FeedbackControllerModule)

FeedbackControllerModule:Init()
