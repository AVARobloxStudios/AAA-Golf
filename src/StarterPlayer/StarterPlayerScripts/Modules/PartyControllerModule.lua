--!strict
-- PartyControllerModule — Client singleton (Sprint 15)
-- Tracks the local party member roster.  Pure state — no UI, no GameBus
-- connection, no server calls, no DataStores.
--
-- Party member fields:
--   userId       number  (positive integer, unique key)
--   displayName  string  (non-empty)
--   isReady      boolean
--   handicap     number  (defaults to 0 if omitted)
--
-- All public getters return copies so callers cannot mutate internal state.
-- AddMember and SetMembers validate each entry and warn-and-skip invalid ones.
--
-- Public API
--   SetMembers(members)          — replace roster with the given array
--   AddMember(member)            — append one member; no-op + warn on bad data
--   RemoveMember(userId)         — remove by userId (no-op if absent)
--   GetMembers()                 → { PartyMember }  (array copy, stable order)
--   GetMember(userId)            → PartyMember?      (copy)
--   SetReady(userId, isReady)    — flip readiness flag; warns if absent
--   IsReady(userId)              → boolean            (false if absent)
--   ClearParty()                 — empty the roster
--   GetPartySize()               → number
--
-- PartyController.client.lua is the thin runner.

-- ── Types ─────────────────────────────────────────────────────────────────────

export type PartyMember = {
	userId:      number,
	displayName: string,
	isReady:     boolean,
	handicap:    number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                  = false
local _members:     { [number]: PartyMember } = {}   -- keyed by userId

-- ── Module ───────────────────────────────────────────────────────────────────

local PartyControllerModule = {}
PartyControllerModule.__index = PartyControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _copyMember(m: PartyMember): PartyMember
	return {
		userId      = m.userId,
		displayName = m.displayName,
		isReady     = m.isReady,
		handicap    = m.handicap,
	}
end

-- Returns true and stores the member if the raw table is valid.
local function _validateAndStore(raw: { [string]: any }): boolean
	local uid = raw["userId"]
	local dn  = raw["displayName"]
	if type(uid) ~= "number" or uid <= 0 then
		warn(("[PartyController] AddMember: userId must be a positive number (got %s)")
			:format(tostring(uid)))
		return false
	end
	if type(dn) ~= "string" or dn == "" then
		warn(("[PartyController] AddMember: displayName must be a non-empty string (got %s)")
			:format(tostring(dn)))
		return false
	end
	_members[uid] = {
		userId      = uid,
		displayName = dn,
		isReady     = raw["isReady"] == true,
		handicap    = type(raw["handicap"]) == "number" and raw["handicap"] or 0,
	}
	return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Replaces the entire roster.  Invalid entries are skipped with a warning.
function PartyControllerModule:SetMembers(members: { { [string]: any } })
	table.clear(_members)
	for _, raw in ipairs(members) do
		_validateAndStore(raw)
	end
end

-- Adds a single member.  Idempotent: a duplicate userId overwrites the entry.
function PartyControllerModule:AddMember(member: { [string]: any })
	_validateAndStore(member)
end

function PartyControllerModule:RemoveMember(userId: number)
	_members[userId] = nil
end

-- Returns a sorted array copy (ascending userId for deterministic ordering).
function PartyControllerModule:GetMembers(): { PartyMember }
	local arr: { PartyMember } = {}
	for _, m in pairs(_members) do
		table.insert(arr, _copyMember(m))
	end
	table.sort(arr, function(a, b) return a.userId < b.userId end)
	return arr
end

function PartyControllerModule:GetMember(userId: number): PartyMember?
	local m = _members[userId]
	if not m then return nil end
	return _copyMember(m)
end

function PartyControllerModule:SetReady(userId: number, isReady: boolean)
	local m = _members[userId]
	if not m then
		warn(("[PartyController] SetReady: userId %d not in party"):format(userId))
		return
	end
	m.isReady = isReady
end

function PartyControllerModule:IsReady(userId: number): boolean
	local m = _members[userId]
	if not m then return false end
	return m.isReady
end

function PartyControllerModule:ClearParty()
	table.clear(_members)
end

function PartyControllerModule:GetPartySize(): number
	local count = 0
	for _ in pairs(_members) do count += 1 end
	return count
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PartyControllerModule:Init()
	if _initialized then
		warn("[PartyController] Init called twice — skipping")
		return
	end
	_initialized = true
	print("[PartyController] ready")
end

function PartyControllerModule:Update(_dt: number) end

function PartyControllerModule:Destroy()
	table.clear(_members)
	_initialized = false
end

return PartyControllerModule
