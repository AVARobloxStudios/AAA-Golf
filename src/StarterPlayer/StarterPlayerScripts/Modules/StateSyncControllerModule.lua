--!strict
-- StateSyncControllerModule — Client singleton (Sprint 19)
-- Registers handlers with EventRouterControllerModule and translates
-- routed GameBus envelopes into PlayerStateController field updates.
--
-- This module is the bridge between the event routing layer (Sprint 18) and
-- the client state snapshot (Sprint 18).  It does not connect to GameBus
-- directly — GameBusBridgeController feeds EventRouter, which calls these
-- handlers.
--
-- Handled event types:
--   StateChanged    — updates gameState (and holeNumber if present); playerId-filtered
--   StrokeCommitted — updates strokeCount, coins, xp if present; playerId-filtered
--   HoleComplete    — advances holeNumber, resets strokeCount; playerId-filtered
--   RoundComplete   — sets gameState = "ROUND_COMPLETE" (broadcast)
--   MatchComplete   — sets gameState = "ROUND_COMPLETE" (broadcast)
--
-- Public API
--   GetSyncedEventCount()  → number
--   ResetSyncCount()       — reset counter to 0
--
-- StateSyncController.client.lua is the thin runner.

local Players = game:GetService("Players")

local EventRouter =
	require(script.Parent.EventRouterControllerModule)

local PSC =
	require(script.Parent.PlayerStateControllerModule)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:  boolean = false
local _syncedCount:  number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local StateSyncControllerModule = {}
StateSyncControllerModule.__index = StateSyncControllerModule

-- ── Private handlers (module-scope so they can be unregistered by identity) ──

local function _handleStateChanged(envelope: any)
	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= Players.LocalPlayer.UserId then return end
	if type(payload.state) == "string" then
		PSC:SetStateField("gameState", payload.state)
	end
	if type(payload.holeNumber) == "number" then
		PSC:SetStateField("holeNumber", payload.holeNumber)
	end
	_syncedCount += 1
end

local function _handleStrokeCommitted(envelope: any)
	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= nil and
	   payload.playerId ~= Players.LocalPlayer.UserId then return end
	if type(payload.strokeCount) == "number" then
		PSC:SetStateField("strokeCount", payload.strokeCount)
	end
	if type(payload.coins) == "number" then
		PSC:SetStateField("coins", payload.coins)
	end
	if type(payload.xp) == "number" then
		PSC:SetStateField("xp", payload.xp)
	end
	_syncedCount += 1
end

local function _handleHoleComplete(envelope: any)
	local payload = envelope.payload
	if type(payload) ~= "table" then return end
	if payload.playerId ~= nil and
	   payload.playerId ~= Players.LocalPlayer.UserId then return end
	if type(payload.holeNumber) == "number" then
		PSC:SetStateField("holeNumber", payload.holeNumber)
	end
	PSC:SetStateField("strokeCount", 0)
	_syncedCount += 1
end

local function _handleRoundComplete(_envelope: any)
	PSC:SetStateField("gameState", "ROUND_COMPLETE")
	_syncedCount += 1
end

local function _handleMatchComplete(_envelope: any)
	PSC:SetStateField("gameState", "ROUND_COMPLETE")
	_syncedCount += 1
end

-- ── Public API ────────────────────────────────────────────────────────────────

function StateSyncControllerModule:GetSyncedEventCount(): number
	return _syncedCount
end

function StateSyncControllerModule:ResetSyncCount()
	_syncedCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function StateSyncControllerModule:Init()
	if _initialized then
		warn("[StateSyncController] Init called twice — skipping")
		return
	end
	_initialized = true
	_syncedCount = 0

	EventRouter:RegisterHandler("StateChanged",    _handleStateChanged)
	EventRouter:RegisterHandler("StrokeCommitted", _handleStrokeCommitted)
	EventRouter:RegisterHandler("HoleComplete",    _handleHoleComplete)
	EventRouter:RegisterHandler("RoundComplete",   _handleRoundComplete)
	EventRouter:RegisterHandler("MatchComplete",   _handleMatchComplete)

	print("[StateSyncController] ready — 5 handlers registered")
end

function StateSyncControllerModule:Update(_dt: number) end

function StateSyncControllerModule:Destroy()
	EventRouter:UnregisterHandler("StateChanged",    _handleStateChanged)
	EventRouter:UnregisterHandler("StrokeCommitted", _handleStrokeCommitted)
	EventRouter:UnregisterHandler("HoleComplete",    _handleHoleComplete)
	EventRouter:UnregisterHandler("RoundComplete",   _handleRoundComplete)
	EventRouter:UnregisterHandler("MatchComplete",   _handleMatchComplete)

	_syncedCount = 0
	_initialized = false
end

return StateSyncControllerModule
