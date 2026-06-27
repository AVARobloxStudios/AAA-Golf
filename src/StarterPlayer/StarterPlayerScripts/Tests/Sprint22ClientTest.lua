--!strict
return function()
-- Sprint22ClientTest — ModuleScript
-- Client smoke tests for Sprint 22: ActionDispatchController,
-- AckBridgeController, and RequestHistoryController.
-- Run via TestRunner.client.lua; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- All sections call Destroy()+Init() at the start for test isolation.
-- No real round or real server response required.

print("[Sprint22ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint22ClientTest]"
local passed = 0
local failed = 0

local function check(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(TAG .. " PASS: " .. label)
	else
		failed += 1
		warn(TAG .. " FAIL: " .. label .. " — " .. tostring(err))
	end
end

local function safeRequire(path: Instance): (boolean, any)
	local ok, result = pcall(require, path :: any)
	if not ok then
		warn(TAG .. " FATAL: require failed — " .. tostring(result))
	end
	return ok, result
end

-- ── Pre-load shared dependencies ──────────────────────────────────────────────

local cacOk, cacResult = safeRequire(
	script.Parent.Parent.Modules.ClientActionControllerModule)
local erOk, erResult = safeRequire(
	script.Parent.Parent.Modules.EventRouterControllerModule)
local sacOk, sacResult = safeRequire(
	script.Parent.Parent.Modules.ServerAckControllerModule)

local CAC: any = cacResult
local ER:  any = erResult
local SAC: any = sacResult

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — ActionDispatchControllerModule  (checks 1–13)
-- ════════════════════════════════════════════════════════════════════════════

local adcOk, adcResult = safeRequire(
	script.Parent.Parent.Modules.ActionDispatchControllerModule)

if adcOk and cacOk then

	local ADC: any = adcResult

	-- Reset state for test isolation.
	ADC:Destroy()
	CAC:Destroy()
	CAC:Init()
	ADC:Init()

	-- 1 ────────────────────────────────────────────────────────────────────
	check("ADC: module loads successfully", function()
		assert(type(ADC) == "table", "expected table, got " .. type(ADC))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("ADC: GetDispatchedCount() is 0 initially", function()
		assert(ADC:GetDispatchedCount() == 0,
			("expected 0, got %d"):format(ADC:GetDispatchedCount()))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAll with empty CAC queue dispatches nothing", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		ADC:DispatchAll()
		assert(ADC:GetDispatchedCount() == 0,
			("expected 0, got %d"):format(ADC:GetDispatchedCount()))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	local swingId: string = ""
	check("ADC: DispatchAll dispatches unsent actions", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		local id = CAC:QueueAction("SwingIntent", { power = 0.8 })
		assert(type(id) == "string" and id ~= "", "CAC:QueueAction failed")
		swingId = id :: string
		ADC:DispatchAll()
		assert(ADC:GetDispatchedCount() == 1,
			("expected 1, got %d"):format(ADC:GetDispatchedCount()))
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAll marks dispatched actions as sent", function()
		assert(CAC:IsActionSent(swingId) == true,
			"expected action to be marked sent after DispatchAll")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAll skips already-sent actions", function()
		local countBefore = ADC:GetDispatchedCount()
		ADC:DispatchAll()
		assert(ADC:GetDispatchedCount() == countBefore,
			("count must not increase on second DispatchAll; before=%d after=%d"):format(
				countBefore, ADC:GetDispatchedCount()))
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("ADC: ResetDispatchedCount resets to 0", function()
		ADC:ResetDispatchedCount()
		assert(ADC:GetDispatchedCount() == 0,
			("expected 0, got %d"):format(ADC:GetDispatchedCount()))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	local holeId: string = ""
	check("ADC: DispatchAction dispatches a specific unsent action", function()
		CAC:ClearActions()
		ADC:ResetDispatchedCount()
		local id = CAC:QueueAction("HoleReady", {})
		assert(type(id) == "string" and id ~= "", "CAC:QueueAction failed")
		holeId = id :: string
		ADC:DispatchAction(holeId)
		assert(ADC:GetDispatchedCount() == 1,
			("expected 1, got %d"):format(ADC:GetDispatchedCount()))
		assert(CAC:IsActionSent(holeId) == true,
			"expected action to be marked sent after DispatchAction")
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAction rejects empty string actionId", function()
		local before = ADC:GetDispatchedCount()
		ADC:DispatchAction("")
		assert(ADC:GetDispatchedCount() == before,
			"count must not change for empty actionId")
	end)

	-- 10 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAction rejects non-string actionId", function()
		local before = ADC:GetDispatchedCount()
		ADC:DispatchAction(123 :: any)
		assert(ADC:GetDispatchedCount() == before,
			"count must not change for non-string actionId")
	end)

	-- 11 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAction warns and no-ops for unknown actionId", function()
		local before = ADC:GetDispatchedCount()
		ADC:DispatchAction("nonexistent_action_id")
		assert(ADC:GetDispatchedCount() == before,
			"count must not change for unknown actionId")
	end)

	-- 12 ────────────────────────────────────────────────────────────────────
	check("ADC: DispatchAction skips already-sent action", function()
		local before = ADC:GetDispatchedCount()
		ADC:DispatchAction(holeId)
		assert(ADC:GetDispatchedCount() == before,
			"count must not change for already-sent action")
	end)

	-- 13 ────────────────────────────────────────────────────────────────────
	check("ADC: Update(0) does not error", function()
		ADC:Update(0)
	end)

else
	warn(TAG .. " SKIP: ActionDispatchControllerModule section — require failed")
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — AckBridgeControllerModule  (checks 14–25)
-- ════════════════════════════════════════════════════════════════════════════

local abcOk, abcResult = safeRequire(
	script.Parent.Parent.Modules.AckBridgeControllerModule)

if abcOk and erOk and sacOk then

	local ABC: any = abcResult

	-- Reset state for test isolation.
	-- ABC:Destroy() unregisters its 3 EventRouter handlers.
	-- SAC:Destroy()+Init() gives us a clean ack table.
	ABC:Destroy()
	SAC:Destroy()
	SAC:Init()
	ABC:Init()

	-- 14 ────────────────────────────────────────────────────────────────────
	check("ABC: module loads successfully", function()
		assert(type(ABC) == "table", "expected table, got " .. type(ABC))
	end)

	-- 15 ────────────────────────────────────────────────────────────────────
	check("ABC: GetReceivedAckCount() is 0 initially", function()
		assert(ABC:GetReceivedAckCount() == 0,
			("expected 0, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 16 ────────────────────────────────────────────────────────────────────
	check("ABC: RequestAck via EventRouter increments count", function()
		ABC:ResetReceivedAckCount()
		SAC:TrackRequest("req_001", "TestRequest")
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { requestId = "req_001", status = "Accepted" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == 1,
			("expected 1, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 17 ────────────────────────────────────────────────────────────────────
	check("ABC: ActionAck via EventRouter increments count", function()
		SAC:TrackRequest("req_002", "SwingIntent")
		ER:RouteEvent({
			eventType = "ActionAck",
			payload   = { requestId = "req_002", status = "Accepted" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == 2,
			("expected 2, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 18 ────────────────────────────────────────────────────────────────────
	check("ABC: ServerAck via EventRouter increments count", function()
		SAC:TrackRequest("req_003", "HoleReady")
		ER:RouteEvent({
			eventType = "ServerAck",
			payload   = { requestId = "req_003", status = "Accepted" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == 3,
			("expected 3, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 19 ────────────────────────────────────────────────────────────────────
	check("ABC: forwarded ack is reflected in ServerAckController", function()
		local ack = SAC:GetAck("req_001")
		assert(type(ack) == "table", "expected AckEntry table from SAC")
		assert(ack.status == "Accepted",
			("expected status 'Accepted', got %q"):format(tostring(ack.status)))
	end)

	-- 20 ────────────────────────────────────────────────────────────────────
	check("ABC: non-table payload does not increment count", function()
		local before = ABC:GetReceivedAckCount()
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = "not a table",
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == before,
			"count must not change for non-table payload")
	end)

	-- 21 ────────────────────────────────────────────────────────────────────
	check("ABC: missing requestId and actionId does not increment count", function()
		local before = ABC:GetReceivedAckCount()
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { status = "Accepted" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == before,
			"count must not change when requestId/actionId missing")
	end)

	-- 22 ────────────────────────────────────────────────────────────────────
	check("ABC: missing status does not increment count", function()
		local before = ABC:GetReceivedAckCount()
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { requestId = "req_999" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == before,
			"count must not change when status missing")
	end)

	-- 23 ────────────────────────────────────────────────────────────────────
	check("ABC: ResetReceivedAckCount resets to 0", function()
		ABC:ResetReceivedAckCount()
		assert(ABC:GetReceivedAckCount() == 0,
			("expected 0, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 24 ────────────────────────────────────────────────────────────────────
	check("ABC: Destroy unregisters handlers — routing after Destroy has no effect", function()
		ABC:Destroy()
		SAC:TrackRequest("req_004", "TestRequest")
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { requestId = "req_004", status = "Accepted" },
			timestamp = os.clock(),
		})
		-- _receivedAckCount was reset to 0 by Destroy and handlers removed.
		assert(ABC:GetReceivedAckCount() == 0,
			("expected 0 after Destroy, got %d"):format(ABC:GetReceivedAckCount()))
	end)

	-- 25 ────────────────────────────────────────────────────────────────────
	check("ABC: re-Init after Destroy re-registers handlers", function()
		ABC:Init()
		assert(ABC:GetReceivedAckCount() == 0,
			"expected 0 after re-Init")
		SAC:TrackRequest("req_005", "TestRequest")
		ER:RouteEvent({
			eventType = "RequestAck",
			payload   = { requestId = "req_005", status = "Rejected" },
			timestamp = os.clock(),
		})
		assert(ABC:GetReceivedAckCount() == 1,
			("expected 1 after re-Init and RouteEvent, got %d"):format(
				ABC:GetReceivedAckCount()))
	end)

else
	warn(TAG .. " SKIP: AckBridgeControllerModule section — require failed")
end

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — RequestHistoryControllerModule  (checks 26–40)
-- ════════════════════════════════════════════════════════════════════════════

local rhcOk, rhcResult = safeRequire(
	script.Parent.Parent.Modules.RequestHistoryControllerModule)

if rhcOk then

	local RHC: any = rhcResult

	-- Reset state for test isolation.
	RHC:Destroy()
	RHC:Init()

	-- 26 ────────────────────────────────────────────────────────────────────
	check("RHC: module loads successfully", function()
		assert(type(RHC) == "table", "expected table, got " .. type(RHC))
	end)

	-- 27 ────────────────────────────────────────────────────────────────────
	check("RHC: GetHistoryCount() is 0 initially", function()
		assert(RHC:GetHistoryCount() == 0,
			("expected 0, got %d"):format(RHC:GetHistoryCount()))
	end)

	-- 28 ────────────────────────────────────────────────────────────────────
	check("RHC: RecordRequest adds an entry", function()
		RHC:RecordRequest("r_001", "SwingIntent", { power = 0.9 })
		assert(RHC:GetHistoryCount() == 1,
			("expected 1, got %d"):format(RHC:GetHistoryCount()))
	end)

	-- 29 ────────────────────────────────────────────────────────────────────
	check("RHC: GetHistory returns correct data", function()
		local hist = RHC:GetHistory()
		assert(type(hist) == "table", "expected table")
		assert(#hist == 1, ("expected 1 entry, got %d"):format(#hist))
		assert(hist[1].requestId   == "r_001",       "wrong requestId")
		assert(hist[1].requestType == "SwingIntent",  "wrong requestType")
		assert(type(hist[1].recordedAt) == "number",  "missing recordedAt")
	end)

	-- 30 ────────────────────────────────────────────────────────────────────
	check("RHC: GetHistory returns a copy — mutating result does not affect state", function()
		local hist = RHC:GetHistory()
		hist[1].requestId = "MUTATED"
		local hist2 = RHC:GetHistory()
		assert(hist2[1].requestId == "r_001",
			"internal state was mutated by caller modification")
	end)

	-- 31 ────────────────────────────────────────────────────────────────────
	check("RHC: GetRequest returns correct entry", function()
		local entry = RHC:GetRequest("r_001")
		assert(type(entry) == "table", "expected table")
		assert(entry ~= nil and entry.requestType == "SwingIntent",
			"wrong requestType in GetRequest result")
	end)

	-- 32 ────────────────────────────────────────────────────────────────────
	check("RHC: GetRequest returns nil for unknown requestId", function()
		local entry = RHC:GetRequest("no_such_id")
		assert(entry == nil, "expected nil for unknown requestId")
	end)

	-- 33 ────────────────────────────────────────────────────────────────────
	check("RHC: GetRequest returns a copy — mutating result does not affect state", function()
		local entry = RHC:GetRequest("r_001")
		assert(entry ~= nil, "expected non-nil entry")
		local e = entry :: any
		e.requestId = "MUTATED"
		local entry2 = RHC:GetRequest("r_001")
		assert(entry2 ~= nil and entry2.requestId == "r_001",
			"internal state was mutated by caller modification")
	end)

	-- 34 ────────────────────────────────────────────────────────────────────
	check("RHC: ClearHistory resets count to 0", function()
		RHC:ClearHistory()
		assert(RHC:GetHistoryCount() == 0,
			("expected 0, got %d"):format(RHC:GetHistoryCount()))
	end)

	-- 35 ────────────────────────────────────────────────────────────────────
	check("RHC: invalid requestId (empty string) is rejected", function()
		local before = RHC:GetHistoryCount()
		RHC:RecordRequest("", "SwingIntent", {})
		assert(RHC:GetHistoryCount() == before,
			"count must not change for empty requestId")
	end)

	-- 36 ────────────────────────────────────────────────────────────────────
	check("RHC: invalid requestId (non-string) is rejected", function()
		local before = RHC:GetHistoryCount()
		RHC:RecordRequest(123 :: any, "SwingIntent", {})
		assert(RHC:GetHistoryCount() == before,
			"count must not change for non-string requestId")
	end)

	-- 37 ────────────────────────────────────────────────────────────────────
	check("RHC: invalid requestType (empty string) is rejected", function()
		local before = RHC:GetHistoryCount()
		RHC:RecordRequest("r_bad", "", {})
		assert(RHC:GetHistoryCount() == before,
			"count must not change for empty requestType")
	end)

	-- 38 ────────────────────────────────────────────────────────────────────
	check("RHC: max 50 entries — oldest discarded when exceeded", function()
		RHC:ClearHistory()
		for i = 1, 51 do
			RHC:RecordRequest(("r_%03d"):format(i), "SwingIntent", {})
		end
		assert(RHC:GetHistoryCount() == 50,
			("expected 50, got %d"):format(RHC:GetHistoryCount()))
		local oldest = RHC:GetHistory()[1]
		assert(oldest.requestId == "r_002",
			("expected 'r_002' as oldest after cap, got %q"):format(
				tostring(oldest and oldest.requestId or "nil")))
	end)

	-- 39 ────────────────────────────────────────────────────────────────────
	check("RHC: Destroy resets history", function()
		RHC:Destroy()
		assert(RHC:GetHistoryCount() == 0,
			("expected 0 after Destroy, got %d"):format(RHC:GetHistoryCount()))
	end)

	-- 40 ────────────────────────────────────────────────────────────────────
	check("RHC: re-Init after Destroy works", function()
		RHC:Init()
		assert(RHC:GetHistoryCount() == 0,
			"expected 0 after re-Init")
		RHC:RecordRequest("r_fresh", "HoleReady", {})
		assert(RHC:GetHistoryCount() == 1,
			"expected 1 after re-Init and RecordRequest")
	end)

else
	warn(TAG .. " SKIP: RequestHistoryControllerModule section — require failed")
end

-- ── Summary ──────────────────────────────────────────────────────────────────

print(TAG .. (" COMPLETE — %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	warn(TAG .. " Some checks failed — see output above")
end

end
