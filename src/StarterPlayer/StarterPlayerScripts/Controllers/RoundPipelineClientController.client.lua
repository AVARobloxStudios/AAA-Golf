--!strict
-- RoundPipelineClientController — LocalScript thin runner (Sprint 27)
-- All logic lives in RoundPipelineClientControllerModule so it can be required
-- and tested independently by Sprint27ClientTest.

local RoundPipelineClientControllerModule =
	require(script.Parent.Parent.Modules.RoundPipelineClientControllerModule)

RoundPipelineClientControllerModule:Init()
