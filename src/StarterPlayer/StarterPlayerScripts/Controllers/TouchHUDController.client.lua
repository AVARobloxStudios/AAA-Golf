--!strict
-- TouchHUDController — LocalScript thin runner (Sprint 16)
-- All logic lives in TouchHUDControllerModule so it can be required and
-- tested independently by Sprint16ClientTest.

local TouchHUDControllerModule =
	require(script.Parent.Parent.Modules.TouchHUDControllerModule)

TouchHUDControllerModule:Init()
