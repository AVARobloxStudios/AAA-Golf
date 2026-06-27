--!strict
-- ServerActionBridgeRunner — thin Script per TDD §3.1

local ServerScriptService = game:GetService("ServerScriptService")
local ServerActionBridgeService =
	require(ServerScriptService.Services.ServerActionBridgeService)
ServerActionBridgeService:Init({})
