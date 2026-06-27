--!strict
-- RequestControllerModule — Client singleton (Sprint 20)
-- Provides validated, counted wrappers around NetworkControllerModule.Send
-- and NetworkControllerModule.Invoke.  This is the single choke-point for
-- all outbound client requests so future sprints can add rate-limiting,
-- retry logic, or request logging in one place.
--
-- RequestController validates that names are non-empty strings before
-- delegating to NetworkController.  NetworkController handles all remote
-- existence checks and warns/no-ops for unknown remote names — RequestController
-- does not duplicate that logic.
--
-- No new remotes are created.  No server modules are modified.
--
-- Public API
--   SendRequest(eventName, payload)        — wraps NetworkController.Send
--   InvokeRequest(functionName, payload)   → any  (wraps NetworkController.Invoke)
--   GetRequestCount()                      → number  (cumulative valid attempts)
--   ResetRequestCount()                    — reset counter to 0
--
-- RequestController.client.lua is the thin runner.

local NetworkController =
	require(script.Parent.NetworkControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean = false
local _requestCount:  number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local RequestControllerModule = {}
RequestControllerModule.__index = RequestControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

-- Fires a RemoteEvent via NetworkController.
-- Increments request count on valid name; warns and no-ops for empty names.
function RequestControllerModule:SendRequest(eventName: string, payload: any)
	if type(eventName) ~= "string" or eventName == "" then
		warn("[RequestController] SendRequest: eventName must be a non-empty string")
		return
	end
	_requestCount += 1
	NetworkController:Send(eventName, payload)
end

-- Invokes a RemoteFunction via NetworkController and returns the result.
-- Increments request count on valid name; warns and returns nil for empty names.
function RequestControllerModule:InvokeRequest(functionName: string, payload: any): any
	if type(functionName) ~= "string" or functionName == "" then
		warn("[RequestController] InvokeRequest: functionName must be a non-empty string")
		return nil
	end
	_requestCount += 1
	return NetworkController:Invoke(functionName, payload)
end

function RequestControllerModule:GetRequestCount(): number
	return _requestCount
end

function RequestControllerModule:ResetRequestCount()
	_requestCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RequestControllerModule:Init()
	if _initialized then
		warn("[RequestController] Init called twice — skipping")
		return
	end
	_initialized  = true
	_requestCount = 0

	print("[RequestController] ready")
end

function RequestControllerModule:Update(_dt: number) end

function RequestControllerModule:Destroy()
	_requestCount = 0
	_initialized  = false
end

return RequestControllerModule
