--!strict
-- Sprint26ServerTest — Server Script smoke tests for Sprint 26.
-- Run in Studio Play Solo mode.  No DataStore or API Services required.
--
-- Covers (26 checks):
--   PipelineMetricsService — module loading, Init, Destroy, all four Increment
--   methods, RecordLatency (valid + invalid), averageLatency running mean,
--   GetSnapshot copy isolation, Reset, double-Init guard, re-Init recovery.
--
-- All checks run immediately (PipelineMetricsService has no player dependency).

local ServerScriptService = game:GetService("ServerScriptService")

local PMS = require(ServerScriptService.Services.PipelineMetricsService)

local TAG = "[Sprint26ServerTest]"

local passed = 0
local failed = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS  " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL  " .. label .. "  (" .. tostring(err) .. ")")
	end
end

-- ── Module-level checks ───────────────────────────────────────────────────────

check("PMS: module loads", function()
	assert(type(PMS) == "table", "expected table")
end)

check("PMS: Init function exists", function()
	assert(type(PMS.Init) == "function")
end)

check("PMS: Destroy function exists", function()
	assert(type(PMS.Destroy) == "function")
end)

check("PMS: Reset function exists", function()
	assert(type(PMS.Reset) == "function")
end)

check("PMS: GetSnapshot function exists", function()
	assert(type(PMS.GetSnapshot) == "function")
end)

check("PMS: IncrementReceived function exists", function()
	assert(type(PMS.IncrementReceived) == "function")
end)

check("PMS: IncrementAccepted function exists", function()
	assert(type(PMS.IncrementAccepted) == "function")
end)

check("PMS: IncrementRejected function exists", function()
	assert(type(PMS.IncrementRejected) == "function")
end)

check("PMS: IncrementExecuted function exists", function()
	assert(type(PMS.IncrementExecuted) == "function")
end)

check("PMS: RecordLatency function exists", function()
	assert(type(PMS.RecordLatency) == "function")
end)

-- ── Init and service tests ────────────────────────────────────────────────────

PMS:Destroy()
PMS:Init({})

check("PMS: GetSnapshot returns all-zero after Init", function()
	local snap = PMS:GetSnapshot()
	assert(snap.receivedCount  == 0, "expected receivedCount=0")
	assert(snap.acceptedCount  == 0, "expected acceptedCount=0")
	assert(snap.rejectedCount  == 0, "expected rejectedCount=0")
	assert(snap.executedCount  == 0, "expected executedCount=0")
	assert(snap.averageLatency == 0, "expected averageLatency=0")
	assert(snap.lastLatency    == 0, "expected lastLatency=0")
end)

check("PMS: IncrementReceived increments receivedCount", function()
	PMS:Reset()
	PMS:IncrementReceived()
	assert(PMS:GetSnapshot().receivedCount == 1,
		("expected 1, got %d"):format(PMS:GetSnapshot().receivedCount))
end)

check("PMS: IncrementAccepted increments acceptedCount", function()
	PMS:Reset()
	PMS:IncrementAccepted()
	assert(PMS:GetSnapshot().acceptedCount == 1,
		("expected 1, got %d"):format(PMS:GetSnapshot().acceptedCount))
end)

check("PMS: IncrementRejected increments rejectedCount", function()
	PMS:Reset()
	PMS:IncrementRejected()
	assert(PMS:GetSnapshot().rejectedCount == 1,
		("expected 1, got %d"):format(PMS:GetSnapshot().rejectedCount))
end)

check("PMS: IncrementExecuted increments executedCount", function()
	PMS:Reset()
	PMS:IncrementExecuted()
	assert(PMS:GetSnapshot().executedCount == 1,
		("expected 1, got %d"):format(PMS:GetSnapshot().executedCount))
end)

check("PMS: RecordLatency sets lastLatency and averageLatency (one sample)", function()
	PMS:Reset()
	PMS:RecordLatency(0.1)
	local snap = PMS:GetSnapshot()
	assert(math.abs(snap.lastLatency    - 0.1) < 0.001,
		("expected lastLatency=0.1, got %.4f"):format(snap.lastLatency))
	assert(math.abs(snap.averageLatency - 0.1) < 0.001,
		("expected averageLatency=0.1, got %.4f"):format(snap.averageLatency))
end)

check("PMS: RecordLatency running mean (two samples: 0.1 + 0.3 → avg 0.2)", function()
	-- Reset was called in previous check; RecordLatency(0.1) was called.
	-- Call RecordLatency(0.3) now — two samples, average = (0.1+0.3)/2 = 0.2.
	PMS:Reset()
	PMS:RecordLatency(0.1)
	PMS:RecordLatency(0.3)
	local snap = PMS:GetSnapshot()
	assert(math.abs(snap.lastLatency    - 0.3) < 0.001,
		("expected lastLatency=0.3, got %.4f"):format(snap.lastLatency))
	assert(math.abs(snap.averageLatency - 0.2) < 0.001,
		("expected averageLatency=0.2, got %.4f"):format(snap.averageLatency))
end)

check("PMS: RecordLatency with negative value is rejected (no-op)", function()
	PMS:Reset()
	PMS:RecordLatency(-0.5)
	local snap = PMS:GetSnapshot()
	assert(snap.lastLatency    == 0, "expected lastLatency=0 after negative input")
	assert(snap.averageLatency == 0, "expected averageLatency=0 after negative input")
end)

check("PMS: GetSnapshot returns independent copy (mutation isolation)", function()
	PMS:Reset()
	PMS:IncrementReceived()
	local snap      = PMS:GetSnapshot()
	local original  = snap.receivedCount
	snap.receivedCount = 999   -- mutate the copy
	local snap2 = PMS:GetSnapshot()
	assert(snap2.receivedCount == original,
		("expected %d, got %d after snapshot mutation"):format(original, snap2.receivedCount))
end)

check("PMS: Reset clears all counters and latency", function()
	PMS:IncrementReceived()
	PMS:IncrementAccepted()
	PMS:RecordLatency(0.5)
	PMS:Reset()
	local snap = PMS:GetSnapshot()
	assert(snap.receivedCount  == 0, "expected receivedCount=0 after Reset")
	assert(snap.acceptedCount  == 0, "expected acceptedCount=0 after Reset")
	assert(snap.lastLatency    == 0, "expected lastLatency=0 after Reset")
	assert(snap.averageLatency == 0, "expected averageLatency=0 after Reset")
end)

check("PMS: Init called twice warns and skips (count unchanged)", function()
	PMS:IncrementReceived()
	local before = PMS:GetSnapshot().receivedCount
	PMS:Init({})   -- second call — should warn and no-op
	assert(PMS:GetSnapshot().receivedCount == before,
		"count should be unchanged after double Init")
end)

check("PMS: Update(0) does not error", function()
	PMS:Update(0)
end)

-- ── Destroy + re-Init recovery ────────────────────────────────────────────────

check("PMS: Destroy resets all counters", function()
	PMS:IncrementExecuted()
	PMS:RecordLatency(1.0)
	PMS:Destroy()
	local snap = PMS:GetSnapshot()
	assert(snap.executedCount  == 0, "expected executedCount=0 after Destroy")
	assert(snap.lastLatency    == 0, "expected lastLatency=0 after Destroy")
	assert(snap.averageLatency == 0, "expected averageLatency=0 after Destroy")
end)

check("PMS: re-Init after Destroy works", function()
	PMS:Init({})
	local snap = PMS:GetSnapshot()
	assert(snap.receivedCount == 0, "expected receivedCount=0 after re-Init")
	assert(snap.executedCount == 0, "expected executedCount=0 after re-Init")
end)

check("PMS: Increment methods work after re-Init", function()
	PMS:IncrementReceived()
	PMS:IncrementAccepted()
	PMS:IncrementRejected()
	PMS:IncrementExecuted()
	local snap = PMS:GetSnapshot()
	assert(snap.receivedCount == 1, "expected receivedCount=1 after re-Init")
	assert(snap.acceptedCount == 1, "expected acceptedCount=1 after re-Init")
	assert(snap.rejectedCount == 1, "expected rejectedCount=1 after re-Init")
	assert(snap.executedCount == 1, "expected executedCount=1 after re-Init")
end)

check("PMS: RecordLatency works after re-Init", function()
	PMS:Reset()
	PMS:RecordLatency(0.25)
	local snap = PMS:GetSnapshot()
	assert(math.abs(snap.lastLatency - 0.25) < 0.001,
		("expected lastLatency=0.25, got %.4f"):format(snap.lastLatency))
	assert(math.abs(snap.averageLatency - 0.25) < 0.001,
		("expected averageLatency=0.25, got %.4f"):format(snap.averageLatency))
end)

-- ── Summary ───────────────────────────────────────────────────────────────────

print(TAG .. " ─────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 26 smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
