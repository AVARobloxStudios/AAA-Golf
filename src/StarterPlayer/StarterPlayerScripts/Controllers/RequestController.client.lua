--!strict
-- RequestController — LocalScript thin runner (Sprint 20)
-- All logic lives in RequestControllerModule so it can be required and
-- tested independently by Sprint20ClientTest.

local RequestControllerModule =
	require(script.Parent.Parent.Modules.RequestControllerModule)

RequestControllerModule:Init()
