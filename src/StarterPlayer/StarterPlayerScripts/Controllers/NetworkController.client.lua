--!strict
-- NetworkController — LocalScript thin runner (Sprint 18)
-- All logic lives in NetworkControllerModule so it can be required and tested
-- independently by Sprint18ClientTest.

local NetworkControllerModule =
	require(script.Parent.Parent.Modules.NetworkControllerModule)

NetworkControllerModule:Init()
