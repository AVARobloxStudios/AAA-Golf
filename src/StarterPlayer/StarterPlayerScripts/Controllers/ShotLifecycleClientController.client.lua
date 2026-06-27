--!strict
-- ShotLifecycleClientController — LocalScript thin runner (Sprint 28)
-- All logic lives in ShotLifecycleClientControllerModule so it can be required
-- and tested independently by Sprint28ClientTest.

local ShotLifecycleClientControllerModule =
	require(script.Parent.Parent.Modules.ShotLifecycleClientControllerModule)

ShotLifecycleClientControllerModule:Init()
