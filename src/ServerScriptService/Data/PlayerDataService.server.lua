--!strict
-- PlayerDataService runner — thin Script per TDD §3.1
-- Wires PlayerAdded / PlayerRemoving and starts the heartbeat via DataStoreBridge.

local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService = require(ServerScriptService.Modules.PlayerDataService)
PlayerDataService:Init()
