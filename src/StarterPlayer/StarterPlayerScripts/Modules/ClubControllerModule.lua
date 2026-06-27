--!strict
-- ClubControllerModule — Client singleton (Sprint 11)
-- Manages the currently selected golf club from a fixed ordered roster.
-- This is a pure state module — no UI and no GameBus connection.
-- InputController drives club switching; HUDController / AimController
-- read the current club for display (future integration sprint).
--
-- Club roster (matches TDD ClubData + Vertical Slice spec):
--   Driver · Wood · Iron · Wedge · Putter
--
-- Public API
--   NextClub()              — advance one step, wraps around
--   PreviousClub()          — retreat one step, wraps around
--   SetClub(name)           — set by name; silently ignores unknown names
--   GetCurrentClub()        — name string of selected club
--   GetAvailableClubs()     — ordered copy of the full roster
--
-- ClubController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Club roster ───────────────────────────────────────────────────────────────

-- Order matches a real golf bag: long clubs first, short last.
local CLUBS: { string } = { "Driver", "Wood", "Iron", "Wedge", "Putter" }

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:  boolean                 = false
local _currentIdx:   number                  = 1     -- index into CLUBS
local _connections:  { RBXScriptConnection } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local ClubControllerModule = {}
ClubControllerModule.__index = ClubControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function ClubControllerModule:NextClub()
	_currentIdx = (_currentIdx % #CLUBS) + 1
	print(("[ClubController] → %s"):format(CLUBS[_currentIdx]))
end

function ClubControllerModule:PreviousClub()
	_currentIdx = ((_currentIdx - 2) % #CLUBS) + 1
	print(("[ClubController] ← %s"):format(CLUBS[_currentIdx]))
end

-- Sets the club by name.  Unknown names are warned and ignored.
function ClubControllerModule:SetClub(name: string)
	for i, club in ipairs(CLUBS) do
		if club == name then
			_currentIdx = i
			print(("[ClubController] set → %s"):format(name))
			return
		end
	end
	warn(("[ClubController] SetClub: unknown club %q — ignored"):format(name))
end

function ClubControllerModule:GetCurrentClub(): string
	return CLUBS[_currentIdx]
end

-- Returns a shallow copy so callers cannot mutate the internal roster.
function ClubControllerModule:GetAvailableClubs(): { string }
	local copy: { string } = {}
	for i, club in ipairs(CLUBS) do
		copy[i] = club
	end
	return copy
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ClubControllerModule:Init()
	if _initialized then
		warn("[ClubController] Init called twice — skipping")
		return
	end
	_initialized = true
	_currentIdx  = 1   -- always start on Driver
	print(("[ClubController] ready (player: %s) — club: %s"):format(
		LocalPlayer.Name, CLUBS[_currentIdx]))
end

function ClubControllerModule:Update(_dt: number) end

function ClubControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	_currentIdx  = 1
	_initialized = false
end

return ClubControllerModule
