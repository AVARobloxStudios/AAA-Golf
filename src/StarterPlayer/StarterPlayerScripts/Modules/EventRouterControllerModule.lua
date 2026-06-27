--!strict
-- EventRouterControllerModule — Client singleton (Sprint 18)
-- A lightweight, synchronous event dispatcher.  Callers register typed
-- handlers; RouteEvent fans out a validated envelope to all matching handlers.
--
-- This module does NOT connect to GameBus directly — it is a pure dispatch
-- table.  A future sprint will wire GameBus.OnClientEvent → RouteEvent so
-- every existing controller can migrate to handler registration instead of
-- holding raw OnClientEvent connections.
--
-- Public API
--   RegisterHandler(eventType, handler)    — add a handler function
--   UnregisterHandler(eventType, handler)  — remove by identity
--   RouteEvent(envelope)                   — dispatch to all matching handlers
--   GetHandlerCount(eventType)             → number
--   ClearHandlers()                        — remove all registered handlers
--
-- EventRouterController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

type Handler = (envelope: any) -> ()

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                   = false
local _handlers:    { [string]: { Handler } } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local EventRouterControllerModule = {}
EventRouterControllerModule.__index = EventRouterControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Registers a handler for a given eventType string.
-- Warns and no-ops for non-string / empty eventType or non-function handler.
function EventRouterControllerModule:RegisterHandler(eventType: string, handler: Handler)
	if type(eventType) ~= "string" or eventType == "" then
		warn("[EventRouterController] RegisterHandler: eventType must be a non-empty string")
		return
	end
	if type(handler) ~= "function" then
		warn("[EventRouterController] RegisterHandler: handler must be a function")
		return
	end
	if not _handlers[eventType] then
		_handlers[eventType] = {}
	end
	table.insert(_handlers[eventType], handler)
end

-- Removes the first matching handler (by identity) for the given eventType.
function EventRouterControllerModule:UnregisterHandler(eventType: string, handler: Handler)
	local list = _handlers[eventType]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == handler then
			table.remove(list, i)
			break
		end
	end
	if _handlers[eventType] and #_handlers[eventType] == 0 then
		_handlers[eventType] = nil :: any
	end
end

-- Dispatches an envelope to all handlers registered for its eventType.
-- Silently no-ops for eventTypes with no registered handlers.
-- Warns and returns early if the envelope is malformed.
function EventRouterControllerModule:RouteEvent(envelope: any)
	if type(envelope) ~= "table" then
		warn("[EventRouterController] RouteEvent: envelope must be a table")
		return
	end
	local eventType = envelope["eventType"]
	if type(eventType) ~= "string" or eventType == "" then
		warn("[EventRouterController] RouteEvent: eventType must be a non-empty string")
		return
	end
	local list = _handlers[eventType]
	if not list then return end
	-- Iterate a snapshot so handlers can safely unregister during dispatch.
	local snapshot = table.clone(list)
	for _, handler in ipairs(snapshot) do
		handler(envelope)
	end
end

function EventRouterControllerModule:GetHandlerCount(eventType: string): number
	local list = _handlers[eventType]
	if not list then return 0 end
	return #list
end

function EventRouterControllerModule:ClearHandlers()
	table.clear(_handlers)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function EventRouterControllerModule:Init()
	if _initialized then
		warn("[EventRouterController] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_handlers)

	print("[EventRouterController] ready")
end

function EventRouterControllerModule:Update(_dt: number) end

function EventRouterControllerModule:Destroy()
	table.clear(_handlers)
	_initialized = false
end

return EventRouterControllerModule
