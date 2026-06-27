--!strict
-- ActionExecutionService — Server-only singleton (Sprint 23)
-- Dispatches validated action envelopes to per-eventType stub handlers and
-- returns an ExecutionResult.  Handlers are placeholders — actual game-side
-- effects (e.g. GameService:OnHoleReady, PhysicsService:SimulateSwing) will be
-- wired in future sprints once the pipeline is stable.
--
-- Every handler is pcall-guarded so one bad handler cannot crash the service.
-- Unknown eventTypes return a graceful failure result rather than erroring.
--
-- Valid eventTypes:
--   SwingIntent | HoleReady | QueueMatchmaking | CancelMatchmaking |
--   SetReady | OpenShop | PreviewItem | EquipCosmetic
--
-- Public API
--   Execute(player, envelope)  → ExecutionResult
--   GetExecutionCount()        → number   (successful known-handler invocations)
--   ResetExecutionCount()
--
-- No runner Script for Sprint 23 — initialized by Sprint23ServerTest or a
-- future runner in Services/.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

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

-- ── Stub handler registry ────────────────────────────────────────────────────

type HandlerFn = (player: Player, payload: any) -> ExecutionResult

local _handlers: { [string]: HandlerFn } = {
	SwingIntent       = function(_p: Player, _pl: any) return _ok("SwingQueued",          nil) end,
	HoleReady         = function(_p: Player, _pl: any) return _ok("HoleReadyAcked",       nil) end,
	QueueMatchmaking  = function(_p: Player, _pl: any) return _ok("MatchmakingQueued",    nil) end,
	CancelMatchmaking = function(_p: Player, _pl: any) return _ok("MatchmakingCancelled", nil) end,
	SetReady          = function(_p: Player, _pl: any) return _ok("ReadySet",             nil) end,
	OpenShop          = function(_p: Player, _pl: any) return _ok("ShopOpened",           nil) end,
	PreviewItem       = function(_p: Player, _pl: any) return _ok("ItemPreviewed",        nil) end,
	EquipCosmetic     = function(_p: Player, _pl: any) return _ok("CosmeticEquipped",     nil) end,
}

-- ── Public API ────────────────────────────────────────────────────────────────

-- Dispatches envelope.eventType to the matching stub handler.
-- Increments _executionCount only for known handlers whose pcall succeeds.
-- Returns a failure result for unknown eventTypes or handler errors — never throws.
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

	Logger:Info("ActionExecutionService", "ready — 8 stub handlers registered")
end

function ActionExecutionService:Update(_dt: number) end

function ActionExecutionService:Destroy()
	_executionCount = 0
	_initialized    = false
end

return ActionExecutionService
