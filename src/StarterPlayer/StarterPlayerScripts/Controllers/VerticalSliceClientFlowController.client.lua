--!strict
-- VerticalSliceClientFlowController — LocalScript thin runner (Sprint 32)
-- All logic lives in VerticalSliceClientFlowControllerModule so it can be
-- required and tested independently by Sprint32ClientTest.

local VerticalSliceClientFlowControllerModule =
	require(script.Parent.Parent.Modules.VerticalSliceClientFlowControllerModule)

VerticalSliceClientFlowControllerModule:Init()
