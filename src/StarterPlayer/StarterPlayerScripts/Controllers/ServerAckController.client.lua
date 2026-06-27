--!strict
-- ServerAckController — LocalScript thin runner (Sprint 20)
-- All logic lives in ServerAckControllerModule so it can be required and
-- tested independently by Sprint20ClientTest.

local ServerAckControllerModule =
	require(script.Parent.Parent.Modules.ServerAckControllerModule)

ServerAckControllerModule:Init()
