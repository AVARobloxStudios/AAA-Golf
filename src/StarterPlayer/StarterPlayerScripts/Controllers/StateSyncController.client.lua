--!strict
-- StateSyncController — LocalScript thin runner (Sprint 19)
-- All logic lives in StateSyncControllerModule so it can be required and
-- tested independently by Sprint19ClientTest.

local StateSyncControllerModule =
	require(script.Parent.Parent.Modules.StateSyncControllerModule)

StateSyncControllerModule:Init()
