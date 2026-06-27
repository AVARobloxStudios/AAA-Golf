--!strict
-- PartyController — LocalScript thin runner (Sprint 15)
-- All logic lives in PartyControllerModule so it can be required and tested
-- independently by Sprint15ClientTest.

local PartyControllerModule =
	require(script.Parent.Parent.Modules.PartyControllerModule)

PartyControllerModule:Init()
