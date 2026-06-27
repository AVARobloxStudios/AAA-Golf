--!strict
-- MobileControlsController — LocalScript thin runner (Sprint 16)
-- All logic lives in MobileControlsControllerModule so it can be required and
-- tested independently by Sprint16ClientTest.

local MobileControlsControllerModule =
	require(script.Parent.Parent.Modules.MobileControlsControllerModule)

MobileControlsControllerModule:Init()
