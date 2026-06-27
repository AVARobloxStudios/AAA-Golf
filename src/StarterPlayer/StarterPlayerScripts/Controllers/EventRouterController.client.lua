--!strict
-- EventRouterController — LocalScript thin runner (Sprint 18)
-- All logic lives in EventRouterControllerModule so it can be required and
-- tested independently by Sprint18ClientTest.

local EventRouterControllerModule =
	require(script.Parent.Parent.Modules.EventRouterControllerModule)

EventRouterControllerModule:Init()
