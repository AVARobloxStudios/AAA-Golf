--!strict
-- LobbyController — LocalScript thin runner (Sprint 15)
-- All logic lives in LobbyControllerModule so it can be required and tested
-- independently by Sprint15ClientTest.

local LobbyControllerModule =
	require(script.Parent.Parent.Modules.LobbyControllerModule)

LobbyControllerModule:Init()
