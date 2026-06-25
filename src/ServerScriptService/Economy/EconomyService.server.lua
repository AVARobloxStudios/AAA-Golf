--!strict
-- EconomyService runner — thin Script per TDD §3.1

local ServerScriptService = game:GetService("ServerScriptService")
local EconomyService = require(ServerScriptService.Modules.EconomyService)
EconomyService:Init()
