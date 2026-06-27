--!strict
-- ActionDispatchController — LocalScript thin runner (Sprint 22)
-- All logic lives in ActionDispatchControllerModule so it can be required and
-- tested independently by Sprint22ClientTest.

local ActionDispatchControllerModule =
	require(script.Parent.Parent.Modules.ActionDispatchControllerModule)

ActionDispatchControllerModule:Init()
