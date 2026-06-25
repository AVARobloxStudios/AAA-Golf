--!strict
-- ScoringService runner — thin Script per TDD §3.1

local ServerScriptService = game:GetService("ServerScriptService")
local ScoringService = require(ServerScriptService.Modules.ScoringService)
ScoringService:Init({})
