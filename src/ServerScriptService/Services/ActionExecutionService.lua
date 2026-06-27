--!strict
-- ActionExecutionService — Server-only singleton (Sprint 23, updated Sprint 25)
-- Dispatches validated action envelopes to per-eventType handlers and returns
-- an ExecutionResult.  Unknown eventTypes return a graceful failure result.
--
-- Sprint 25 change: HoleReady and SwingIntent now call real GameService methods.
--   HoleReady   → GameService:OnHoleReady(player)      (TEE_OFF → SWING)
--   SwingIntent → validates payload, then GameService:OnSwingFired(player)
--                 Physics simulation is NOT triggered here — EventBusHandler's
--                 existing GameBus.OnServerEvent listener owns that path; calling
--                 SimulateSwing from AES would double-execute physics.
--
-- Every handler is pcall-guarded so one bad handler cannot crash the service.
--
-- Valid eventTypes (8):
--   HoleReady | SwingIntent | QueueMatchmaking | CancelMatchmaking |
--   SetReady | OpenShop | PreviewItem | EquipCosmetic
--
-- Public API
--   Execute(player, envelope)  → ExecutionResult
--   GetExecutionCount()        → number   (known-handler invocations that returned normally)
--   ResetExecutionCount()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger      = require(ReplicatedStorage.Shared.Logger)
local GameService = require(ServerScriptService.Modules.GameService)

-- ── Types ─────────────────────────────────────────────────────────────────────

export type ExecutionResult = {
	success: boolean,
	status:  string,
	payload: any,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _executionCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ActionExecutionService = {}
ActionExecutionService.__index = ActionExecutionService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _ok(status: string, payload: any): ExecutionResult
	return { success = true, status = status, payload = payload }
end

local function _fail(status: string): ExecutionResult
	return { success = false, status = status, payload = nil }
end

-- Returns a consistent failure status from a pcall error string.
local function _gsError(errMsg: string): ExecutionResult
	if tostring(errMsg):find("no active session") then
		return _fail("NoSession")
	end
	return _fail("StateError")
end

-- ── Handler registry ─────────────────────────────────────────────────────────

type HandlerFn = (player: Player, payload: any) -> ExecutionResult

local _handlers: { [string]: HandlerFn } = {

	-- ── Real handlers (Sprint 25) ─────────────────────────────────────────

	HoleReady = function(player: Player, payload: any): ExecutionResult
		if type(payload) ~= "table" then
			return _fail("InvalidPayload")
		end
		local ok, errMsg = pcall(function()
			GameService:OnHoleReady(player)
		end)
		if not ok then
			return _gsError(tostring(errMsg))
		end
		return _ok("HoleReadyAcked", nil)
	end,

	SwingIntent = function(player: Player, payload: any): ExecutionResult
		if type(payload) ~= "table" then
			return _fail("InvalidPayload")
		end
		if typeof(payload.aimVector) ~= "Vector3" then
			return _fail("InvalidAimVector")
		end
		if type(payload.power) ~= "number"
			or payload.power < 0
			or payload.power > 1 then
			return _fail("InvalidPower")
		end
		if payload.clubName ~= nil
			and (type(payload.clubName) ~= "string" or payload.clubName == "") then
			return _fail("InvalidClubName")
		end
		-- Physics simulation is handled by EventBusHandler's GameBus.OnServerEvent
		-- listener.  AES only drives the GameService state transition here.
		local ok, errMsg = pcall(function()
			GameService:OnSwingFired(player)
		end)
		if not ok then
			return _gsError(tostring(errMsg))
		end
		return _ok("SwingQueued", nil)
	end,

	-- ── Stub handlers (Sprint 23, unchanged) ─────────────────────────────

	QueueMatchmaking  = function(_p: Player, _pl: any) return _ok("MatchmakingQueued",    nil) end,
	CancelMatchmaking = function(_p: Player, _pl: any) return _ok("MatchmakingCancelled", nil) end,
	SetReady          = function(_p: Player, _pl: any) return _ok("ReadySet",             nil) end,
	OpenShop          = function(_p: Player, _pl: any) return _ok("ShopOpened",           nil) end,
	PreviewItem       = function(_p: Player, _pl: any) return _ok("ItemPreviewed",        nil) end,
	EquipCosmetic     = function(_p: Player, _pl: any) return _ok("CosmeticEquipped",     nil) end,
}

-- ── Public API ────────────────────────────────────────────────────────────────

-- Dispatches envelope.eventType to the matching handler.
-- Increments _executionCount for every handler invocation that does not throw.
-- Returns a failure result for unknown eventTypes or throwing handlers — never throws.
function ActionExecutionService:Execute(player: Player, envelope: any): ExecutionResult
	if not _initialized then
		return _fail("NotInitialized")
	end
	local eventType = envelope.eventType
	local handler   = _handlers[eventType]
	if not handler then
		Logger:Warn("ActionExecutionService",
			("unknown eventType %q from %s — returning failure"):format(
				tostring(eventType), player.Name))
		return _fail("UnknownEvent")
	end
	local ok, result = pcall(handler, player, envelope.payload)
	if not ok then
		Logger:Warn("ActionExecutionService",
			("handler %q errored for %s: %s"):format(
				tostring(eventType), player.Name, tostring(result)))
		return _fail("HandlerError")
	end
	_executionCount += 1
	Logger:Debug("ActionExecutionService",
		("executed %q for %s → %s"):format(
			tostring(eventType), player.Name,
			tostring((result :: ExecutionResult).status)))
	return result :: ExecutionResult
end

function ActionExecutionService:GetExecutionCount(): number
	return _executionCount
end

function ActionExecutionService:ResetExecutionCount()
	_executionCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ActionExecutionService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[ActionExecutionService] Init called twice — skipping")
		return
	end
	_initialized    = true
	_executionCount = 0
	Logger:Info("ActionExecutionService",
		"ready — 2 real handlers (HoleReady, SwingIntent) + 6 stubs")
end

function ActionExecutionService:Update(_dt: number) end

function ActionExecutionService:Destroy()
	_executionCount = 0
	_initialized    = false
end

return ActionExecutionService
