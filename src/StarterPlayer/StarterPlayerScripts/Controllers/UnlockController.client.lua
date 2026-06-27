--!strict
-- UnlockController — LocalScript thin runner (Sprint 13)
-- All logic lives in UnlockControllerModule so it can be required and
-- tested independently by Sprint13ClientTest.

local UnlockControllerModule =
	require(script.Parent.Parent.Modules.UnlockControllerModule)

UnlockControllerModule:Init()
