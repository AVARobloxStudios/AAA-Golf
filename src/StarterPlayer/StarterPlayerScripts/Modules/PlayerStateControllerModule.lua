--!strict
-- PlayerStateControllerModule — Client singleton (Sprint 18)
-- Maintains a client-side snapshot of the local player's in-game state.
-- Pure state — no server calls, no UI, no GameBus connection.
--
-- The snapshot is the single source of truth for the client integration layer.
-- Future sprints will populate it from GameBus StateChanged events so every
-- controller can read consistent state rather than each maintaining its own.
--
-- All getters return copies or scalar values — callers cannot mutate internal
-- state.  Unknown field names are rejected with a warning.
--
-- Default state:
--   gameState      = "LOBBY"     holeNumber     = 1
--   strokeCount    = 0           currentClub    = "Driver"
--   aimAngle       = 0           swingPower     = 0
--   coins          = 0           xp             = 0
--   selectedCourse = "course_1"  isReady        = false
--
-- Public API
--   SetStateField(fieldName, value)    — update one field; warns on unknown names
--   GetStateField(fieldName)           → any  (nil for unknown fields)
--   ApplySnapshot(snapshot)            — merge a partial or full snapshot
--   GetSnapshot()                      → { [string]: any }  (shallow copy)
--   ResetState()                       — restore all fields to defaults
--
-- PlayerStateController.client.lua is the thin runner.

-- ── Default state ─────────────────────────────────────────────────────────────

local DEFAULT_STATE: { [string]: any } = {
	gameState      = "LOBBY",
	holeNumber     = 1,
	strokeCount    = 0,
	currentClub    = "Driver",
	aimAngle       = 0,
	swingPower     = 0,
	coins          = 0,
	xp             = 0,
	selectedCourse = "course_1",
	isReady        = false,
}

-- O(1) membership check derived from DEFAULT_STATE keys.
local VALID_FIELDS: { [string]: boolean } = {}
for k in pairs(DEFAULT_STATE) do
	VALID_FIELDS[k] = true
end

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean            = false
local _state:       { [string]: any }  = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local PlayerStateControllerModule = {}
PlayerStateControllerModule.__index = PlayerStateControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _seedDefaults()
	for k, v in pairs(DEFAULT_STATE) do
		_state[k] = v
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Updates a single field.  Warns and no-ops for unknown field names.
function PlayerStateControllerModule:SetStateField(fieldName: string, value: any)
	if not VALID_FIELDS[fieldName] then
		warn(("[PlayerStateController] SetStateField: unknown field %q"):format(
			tostring(fieldName)))
		return
	end
	_state[fieldName] = value
end

-- Returns the current value of a field, or nil for unknown fields.
function PlayerStateControllerModule:GetStateField(fieldName: string): any
	if not VALID_FIELDS[fieldName] then return nil end
	return _state[fieldName]
end

-- Merges a partial or full state snapshot.  Unknown keys are silently skipped.
function PlayerStateControllerModule:ApplySnapshot(snapshot: { [string]: any })
	if type(snapshot) ~= "table" then
		warn("[PlayerStateController] ApplySnapshot: expected table — ignored")
		return
	end
	for field, value in pairs(snapshot) do
		if type(field) == "string" and VALID_FIELDS[field] then
			_state[field] = value
		end
	end
end

-- Returns a shallow copy of the entire state snapshot.
function PlayerStateControllerModule:GetSnapshot(): { [string]: any }
	local copy: { [string]: any } = {}
	for k, v in pairs(_state) do
		copy[k] = v
	end
	return copy
end

-- Restores all fields to their default values.
function PlayerStateControllerModule:ResetState()
	_seedDefaults()
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PlayerStateControllerModule:Init()
	if _initialized then
		warn("[PlayerStateController] Init called twice — skipping")
		return
	end
	_initialized = true
	_seedDefaults()

	print("[PlayerStateController] ready")
end

function PlayerStateControllerModule:Update(_dt: number) end

function PlayerStateControllerModule:Destroy()
	table.clear(_state)
	_initialized = false
end

return PlayerStateControllerModule
