--!strict
-- ControllerBridgeControllerModule — Client singleton (Sprint 19)
-- A named-callback registry that future integration sprints use to wire
-- actions between existing controllers without creating circular requires.
--
-- Each bridge is a named function.  RunBridge(name, payload) calls it
-- and returns the result.  This keeps integrations explicit, auditable,
-- and trivially testable without live gameplay.
--
-- Public API
--   IsReady()                          → boolean
--   RegisterBridge(name, callback)     — store a named integration callback
--   RunBridge(name, payload)           → any  (nil if name unknown)
--   GetRegisteredBridgeCount()         → number
--   ClearBridges()                     — remove all registered bridges
--
-- ControllerBridgeController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

type BridgeCallback = (payload: any) -> any

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                     = false
local _ready:       boolean                     = false
local _bridges:     { [string]: BridgeCallback } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local ControllerBridgeControllerModule = {}
ControllerBridgeControllerModule.__index = ControllerBridgeControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function ControllerBridgeControllerModule:IsReady(): boolean
	return _ready
end

-- Registers a named bridge callback.
-- Warns and no-ops for empty names or non-function callbacks.
function ControllerBridgeControllerModule:RegisterBridge(
	name:     string,
	callback: BridgeCallback
)
	if type(name) ~= "string" or name == "" then
		warn("[ControllerBridgeController] RegisterBridge: name must be a non-empty string")
		return
	end
	if type(callback) ~= "function" then
		warn("[ControllerBridgeController] RegisterBridge: callback must be a function")
		return
	end
	_bridges[name] = callback
end

-- Calls the named bridge with payload and returns the result.
-- Warns and returns nil for unknown bridge names.
function ControllerBridgeControllerModule:RunBridge(name: string, payload: any): any
	local cb = _bridges[name]
	if not cb then
		warn(("[ControllerBridgeController] RunBridge: unknown bridge %q"):format(
			tostring(name)))
		return nil
	end
	return cb(payload)
end

function ControllerBridgeControllerModule:GetRegisteredBridgeCount(): number
	local count = 0
	for _ in pairs(_bridges) do count += 1 end
	return count
end

function ControllerBridgeControllerModule:ClearBridges()
	table.clear(_bridges)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ControllerBridgeControllerModule:Init()
	if _initialized then
		warn("[ControllerBridgeController] Init called twice — skipping")
		return
	end
	_initialized = true
	_ready       = true
	table.clear(_bridges)

	print("[ControllerBridgeController] ready")
end

function ControllerBridgeControllerModule:Update(_dt: number) end

function ControllerBridgeControllerModule:Destroy()
	table.clear(_bridges)
	_ready       = false
	_initialized = false
end

return ControllerBridgeControllerModule
