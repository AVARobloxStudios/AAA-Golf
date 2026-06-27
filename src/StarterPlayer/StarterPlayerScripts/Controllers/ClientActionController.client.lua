--!strict
-- ClientActionController — LocalScript thin runner (Sprint 20)
-- All logic lives in ClientActionControllerModule so it can be required and
-- tested independently by Sprint20ClientTest.

local ClientActionControllerModule =
	require(script.Parent.Parent.Modules.ClientActionControllerModule)

ClientActionControllerModule:Init()
