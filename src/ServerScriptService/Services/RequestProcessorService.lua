--!strict
-- RequestProcessorService — Server-only singleton (Sprint 23)
-- The server-side entry point for the client action pipeline.
-- Receives action envelopes (fired by the client's ActionDispatchController via
-- GameBus), validates them, forwards valid ones to ActionExecutionService, and
-- sends the result through ResponseDispatchService as an acknowledgement.
--
-- Validation requirements:
--   envelope       — must be a table
--   envelope.actionId   — must be a non-empty string
--   envelope.eventType  — must be a non-empty string
--   envelope.payload    — must be a table
-- Malformed envelopes are warned and dropped; _processedCount is not incremented.
--
-- In production this module would be wired to GameBus.OnServerEvent alongside
-- EventBusHandler.  For Sprint 23 it is exercised directly by Sprint23ServerTest
-- and future wiring can add a runner Script.
--
-- Public API
--   ProcessRequest(player, envelope)  → boolean  (true = processed, false = rejected)
--   GetProcessedCount()               → number
--   ResetProcessedCount()
--
-- No runner Script for Sprint 23 — initialized by Sprint23ServerTest or a
-- future runner in Services/.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local AES = require(ServerScriptService.Services.ActionExecutionService)
local RDS = require(ServerScriptService.Services.ResponseDispatchService)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _processedCount: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local RequestProcessorService = {}
RequestProcessorService.__index = RequestProcessorService

-- ── Public API ────────────────────────────────────────────────────────────────

-- Validates and processes one action envelope from a client player.
-- Returns true on success, false if the envelope was rejected.
function RequestProcessorService:ProcessRequest(player: Player, envelope: any): boolean
	if not _initialized then
		warn("[RequestProcessorService] ProcessRequest called before Init — skipping")
		return false
	end

	-- ── Validation ────────────────────────────────────────────────────────────

	if type(envelope) ~= "table" then
		warn(("[RequestProcessorService] non-table envelope from %s — rejecting"):format(
			player.Name))
		return false
	end

	if type(envelope.actionId) ~= "string" or envelope.actionId == "" then
		warn(("[RequestProcessorService] missing actionId from %s — rejecting"):format(
			player.Name))
		return false
	end

	if type(envelope.eventType) ~= "string" or envelope.eventType == "" then
		warn(("[RequestProcessorService] missing eventType from %s — rejecting"):format(
			player.Name))
		return false
	end

	if type(envelope.payload) ~= "table" then
		warn(("[RequestProcessorService] payload must be a table from %s — rejecting"):format(
			player.Name))
		return false
	end

	-- ── Dispatch ─────────────────────────────────────────────────────────────

	_processedCount += 1
	Logger:Debug("RequestProcessorService",
		("processing %q actionId=%s from %s"):format(
			envelope.eventType, envelope.actionId, player.Name))

	local result = AES:Execute(player, envelope)
	RDS:DispatchResult(player, envelope.actionId, result)

	return true
end

function RequestProcessorService:GetProcessedCount(): number
	return _processedCount
end

function RequestProcessorService:ResetProcessedCount()
	_processedCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RequestProcessorService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[RequestProcessorService] Init called twice — skipping")
		return
	end
	_initialized    = true
	_processedCount = 0

	Logger:Info("RequestProcessorService", "ready")
end

function RequestProcessorService:Update(_dt: number) end

function RequestProcessorService:Destroy()
	_processedCount = 0
	_initialized    = false
end

return RequestProcessorService
