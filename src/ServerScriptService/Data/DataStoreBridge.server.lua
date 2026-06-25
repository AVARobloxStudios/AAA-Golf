--!strict
-- DataStoreBridge runner — thin Script per TDD §3.1
-- Initialises DataStoreBridge (heartbeat + BindToClose) at server start.

local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreBridge = require(ServerScriptService.Modules.DataStoreBridge)
DataStoreBridge:Init()
