--!strict
-- PipelineMetricsService — Server-only singleton (Sprint 26)
-- Tracks runtime pipeline statistics: message counts and round-trip latency.
-- Pure metrics tracking — no gameplay logic, no player state.
--
-- averageLatency is a running arithmetic mean across all RecordLatency samples
-- since the last Reset().  GetSnapshot() returns an independent copy so callers
-- cannot mutate internal state.
--
-- Public API
--   IncrementReceived()
--   IncrementAccepted()
--   IncrementRejected()
--   IncrementExecuted()
--   RecordLatency(seconds)
--   GetSnapshot()    → { receivedCount, acceptedCount, rejectedCount,
--                         executedCount, averageLatency, lastLatency }
--   Reset()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:    boolean = false
local _receivedCount:  number  = 0
local _acceptedCount:  number  = 0
local _rejectedCount:  number  = 0
local _executedCount:  number  = 0
local _totalLatency:   number  = 0
local _latencySamples: number  = 0
local _lastLatency:    number  = 0
local _averageLatency: number  = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local PipelineMetricsService = {}
PipelineMetricsService.__index = PipelineMetricsService

-- ── Public API ────────────────────────────────────────────────────────────────

function PipelineMetricsService:IncrementReceived()
	if not _initialized then return end
	_receivedCount += 1
end

function PipelineMetricsService:IncrementAccepted()
	if not _initialized then return end
	_acceptedCount += 1
end

function PipelineMetricsService:IncrementRejected()
	if not _initialized then return end
	_rejectedCount += 1
end

function PipelineMetricsService:IncrementExecuted()
	if not _initialized then return end
	_executedCount += 1
end

-- Records one latency sample in seconds. Negative values are rejected.
function PipelineMetricsService:RecordLatency(seconds: number)
	if not _initialized then return end
	if type(seconds) ~= "number" or seconds < 0 then
		Logger:Warn("PipelineMetricsService",
			("RecordLatency: expected non-negative number, got %s"):format(tostring(seconds)))
		return
	end
	_lastLatency     = seconds
	_latencySamples += 1
	_totalLatency   += seconds
	_averageLatency  = _totalLatency / _latencySamples
end

-- Returns an independent copy of the current metrics snapshot.
-- Mutating the returned table does not affect internal state.
function PipelineMetricsService:GetSnapshot(): { [string]: number }
	return {
		receivedCount  = _receivedCount,
		acceptedCount  = _acceptedCount,
		rejectedCount  = _rejectedCount,
		executedCount  = _executedCount,
		averageLatency = _averageLatency,
		lastLatency    = _lastLatency,
	}
end

-- Resets all counters and latency tracking to zero.
function PipelineMetricsService:Reset()
	_receivedCount  = 0
	_acceptedCount  = 0
	_rejectedCount  = 0
	_executedCount  = 0
	_totalLatency   = 0
	_latencySamples = 0
	_lastLatency    = 0
	_averageLatency = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PipelineMetricsService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[PipelineMetricsService] Init called twice — skipping")
		return
	end
	_initialized = true
	PipelineMetricsService:Reset()

	Logger:Info("PipelineMetricsService", "ready")
end

function PipelineMetricsService:Update(_dt: number) end

function PipelineMetricsService:Destroy()
	PipelineMetricsService:Reset()
	_initialized = false
end

return PipelineMetricsService
