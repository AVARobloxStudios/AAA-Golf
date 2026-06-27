--!strict
-- AudioController — LocalScript thin runner (Sprint 17)
-- All logic lives in AudioControllerModule so it can be required and tested
-- independently by Sprint17ClientTest.

local AudioControllerModule =
	require(script.Parent.Parent.Modules.AudioControllerModule)

AudioControllerModule:Init()
