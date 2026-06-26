--!strict
-- EventBusHandler — Server-only singleton
-- Owns the single GameBus.OnServerEvent connection and routes validated
-- inbound envelopes to the appropriate service. Per TDD §4.1:
--   HoleReady   → GameService:OnHoleReady(player)
--   SwingIntent → PhysicsService:SimulateSwing then GameService:OnSwingFired
-- Unknown eventTypes are warned and dropped. Handler errors are caught so one
-- bad payload cannot disconnect the listener.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types          = require(ReplicatedStorage.Shared.Modules.Types)
local ClubData       = require(ReplicatedStorage.Shared.Modules.ClubData)
local GameService    = require(ServerScriptService.Modules.GameService)
local PhysicsService = require(ServerScriptService.Modules.PhysicsService)

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

local _connection: RBXScriptConnection? = nil

local EventBusHandler = {}
EventBusHandler.__index = EventBusHandler

-- ── Private handlers ────────────────────────────────────────────────────────

local function _handleHoleReady(player: Player, _payload: any)
	GameService:OnHoleReady(player)
end

local function _handleSwingIntent(player: Player, payload: any)
	if type(payload) ~= "table" then
		warn("[EventBusHandler] SwingIntent: payload must be a table — ignoring")
		return
	end
	if typeof(payload.aimVector) ~= "Vector3" then
		warn("[EventBusHandler] SwingIntent: aimVector must be a Vector3 — ignoring")
		return
	end
	if type(payload.power) ~= "number" then
		warn("[EventBusHandler] SwingIntent: power must be a number — ignoring")
		return
	end
	if type(payload.accuracy) ~= "number" then
		warn("[EventBusHandler] SwingIntent: accuracy must be a number — ignoring")
		return
	end
	if type(payload.clubId) ~= "string" then
		warn("[EventBusHandler] SwingIntent: clubId must be a string — ignoring")
		return
	end

	local clubId: string = payload.clubId :: string
	local club: any = ClubData.GetClub(clubId)
	if not club then
		warn(("[EventBusHandler] SwingIntent: unknown clubId %q — ignoring"):format(clubId))
		return
	end

	-- Server-authoritative start position. For the VS every shot launches from
	-- the hole tee; a production build would expose GameService:GetCurrentLie().
	local teePos: Vector3? = GameService:GetTeePosition(player) :: Vector3?
	local startCFrame = CFrame.new(teePos or Vector3.new(0, 5, 0))

	local ts: number = if type(payload.timestamp) == "number"
		then payload.timestamp :: number
		else os.time()

	local intent: Types.SwingIntent = {
		eventType = "SwingIntent",
		aimVector = payload.aimVector :: Vector3,
		power     = payload.power     :: number,
		accuracy  = payload.accuracy  :: number,
		clubId    = clubId,
		timestamp = ts,
	}

	PhysicsService:SimulateSwing(player, intent, club, startCFrame)
	GameService:OnSwingFired(player)
end

-- ── Dispatch table ─────────────────────────────────────────────────────────

type HandlerFn = (player: Player, payload: any) -> ()

local _handlers: { [string]: HandlerFn? } = {
	HoleReady   = _handleHoleReady,
	SwingIntent = _handleSwingIntent,
}

-- ── Public API ─────────────────────────────────────────────────────────────

-- Validates the envelope and routes to the matching handler.
-- Underscore prefix exposes it to Sprint5Test without a live client.
function EventBusHandler:_dispatch(player: Player, envelope: any)
	if type(envelope) ~= "table" then
		warn("[EventBusHandler] non-table envelope from " .. player.Name .. " — ignoring")
		return
	end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then
		warn("[EventBusHandler] missing string eventType from " .. player.Name .. " — ignoring")
		return
	end
	local handler: HandlerFn? = _handlers[eventType]
	if not handler then
		warn(("[EventBusHandler] unknown eventType %q from %s — ignoring"):format(
			eventType, player.Name))
		return
	end
	local ok, err = pcall(handler, player, envelope.payload)
	if not ok then
		warn(("[EventBusHandler] %q handler errored for %s: %s"):format(
			eventType, player.Name, tostring(err)))
	end
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function EventBusHandler:Init(_deps: { [string]: any })
	if _connection then
		warn("[EventBusHandler] already connected — skipping duplicate Init")
		return
	end
	_connection = GameBus.OnServerEvent:Connect(function(player: Player, envelope: any)
		EventBusHandler:_dispatch(player, envelope)
	end)
end

function EventBusHandler:Update(_dt: number) end

function EventBusHandler:Destroy()
	if _connection then
		_connection:Disconnect()
		_connection = nil
	end
end

return EventBusHandler
