--!strict
-- SwingController — LocalScript thin runner (Sprint 6)
-- All logic lives in SwingControllerModule so it can be required and tested
-- independently by Sprint6ClientTest.

local SwingControllerModule =
	require(script.Parent.Parent.Modules.SwingControllerModule)

SwingControllerModule:Init()
