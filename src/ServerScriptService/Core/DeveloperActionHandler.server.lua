--!strict
-- DeveloperActionHandler — Server Script (Sprint 33 + Sprint 34)
-- Listens on the DeveloperAction RemoteEvent and routes client developer
-- actions to PlayableHoleService.  Separate from EventBusHandler so
-- developer actions do not pollute the gameplay GameBus listener with warnings.
--
-- Action payloads:
--   { action = "StartPlayableHole" }
--   { action = "ShootBall", direction = Vector3, power = number }   — Sprint 33 compat
--   { action = "ShootBallSwing", swingResult = {table} }            — Sprint 34
--   { action = "Reset" }

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayableHoleService = require(ServerScriptService.Services.PlayableHoleService)

local DeveloperAction: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.DeveloperAction :: RemoteEvent

local DEFAULT_POWER: number = 60  -- studs/sec fallback if client omits power

DeveloperAction.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" then return end
	local action = payload.action
	if type(action) ~= "string" then return end

	print(("[DeveloperAction] %s from %s"):format(action, player.Name))

	if action == "StartPlayableHole" then
		PlayableHoleService:StartPlayableHole(player)

	elseif action == "ShootBall" then
		local rawDir = payload.direction
		local rawPow = payload.power
		local direction: Vector3 = if typeof(rawDir) == "Vector3"
			then rawDir :: Vector3
			else Vector3.new(0, 0.3, -1).Unit
		local power: number = if type(rawPow) == "number"
			then rawPow :: number
			else DEFAULT_POWER
		PlayableHoleService:ShootBall(player, direction, power)

	elseif action == "ShootBallSwing" then
		-- Sprint 34: full SwingResult from client analyzer
		local sr = payload.swingResult
		if type(sr) == "table" then
			PlayableHoleService:ShootBall(player, sr :: any)
		else
			warn("[DeveloperActionHandler] ShootBallSwing: missing or invalid swingResult")
		end

	elseif action == "Reset" then
		PlayableHoleService:ResetPlayer(player)
	end
end)
