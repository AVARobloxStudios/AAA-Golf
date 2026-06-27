--!strict
-- ClubController — LocalScript thin runner (Sprint 11)
-- All logic lives in ClubControllerModule so it can be required and tested
-- independently by Sprint11ClientTest.

local ClubControllerModule =
	require(script.Parent.Parent.Modules.ClubControllerModule)

ClubControllerModule:Init()
