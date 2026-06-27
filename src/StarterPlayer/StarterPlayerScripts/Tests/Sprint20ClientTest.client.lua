--!strict
-- Sprint20ClientTest — LocalScript
-- Client smoke tests for Sprint 20: ClientActionController, RequestController,
-- and ServerAckController.
-- Run in Play mode; output appears in the Roblox Studio Output window.
--
-- Thin runners call Module:Init() before this script loads.
-- No real round or real server response required.
-- RequestController tests use a non-existent remote name so NCM warns and
-- no-ops rather than firing a real FireServer call.

print("[Sprint20ClientTest] Script started")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local TAG    = "[Sprint20ClientTest]"
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

-- ════════════════════════════════════════════════════════════════════════════
-- Section 1 — ClientActionControllerModule  (checks 1–15)
-- ════════════════════════════════════════════════════════════════════════════

local cacOk, cacResult = safeRequire(
	script.Parent.Parent.Modules.ClientActionControllerModule)

if cacOk then

	local CAC: any = cacResult

	-- 1 ────────────────────────────────────────────────────────────────────
	check("CAC: module loads successfully", function()
		assert(type(CAC) == "table", "expected table, got " .. type(CAC))
	end)

	-- 2 ────────────────────────────────────────────────────────────────────
	check("CAC: GetActionCount() is 0 initially", function()
		assert(CAC:GetActionCount() == 0,
			("expected 0, got %d"):format(CAC:GetActionCount()))
	end)

	-- 3 ────────────────────────────────────────────────────────────────────
	check("CAC: GetQueuedActions() returns empty array initially", function()
		local actions = CAC:GetQueuedActions()
		assert(type(actions) == "table", "expected table")
		assert(#actions == 0, ("expected length 0, got %d"):format(#actions))
	end)

	-- 4 ────────────────────────────────────────────────────────────────────
	check("CAC: QueueAction with invalid type returns nil", function()
		local id = CAC:QueueAction("InvalidActionXYZ", {})
		assert(id == nil, "expected nil for invalid action type")
	end)

	-- 5 ────────────────────────────────────────────────────────────────────
	check("CAC: GetActionCount() unchanged after invalid QueueAction", function()
		assert(CAC:GetActionCount() == 0,
			"invalid QueueAction must not add to queue")
	end)

	-- 6 ────────────────────────────────────────────────────────────────────
	local firstId: string = ""
	check("CAC: QueueAction with valid type returns a string actionId", function()
		local id = CAC:QueueAction("SwingIntent", { power = 0.75 })
		assert(type(id) == "string" and id ~= "",
			"expected non-empty string actionId")
		firstId = id :: string
	end)

	-- 7 ────────────────────────────────────────────────────────────────────
	check("CAC: GetActionCount() is 1 after one QueueAction", function()
		assert(CAC:GetActionCount() == 1,
			("expected 1, got %d"):format(CAC:GetActionCount()))
	end)

	-- 8 ────────────────────────────────────────────────────────────────────
	local secondId: string = ""
	check("CAC: Generated actionIds are unique across calls", function()
		local id2 = CAC:QueueAction("HoleReady", {})
		assert(type(id2) == "string", "expected string")
		assert(id2 ~= firstId, "second actionId must differ from first")
		secondId = id2 :: string
	end)

	-- 9 ────────────────────────────────────────────────────────────────────
	check("CAC: GetQueuedActions() entry has correct actionType and sent=false", function()
		local actions = CAC:GetQueuedActions()
		local found: any = nil
		for _, entry in ipairs(actions) do
			if entry.actionId == firstId then found = entry end
		end
		assert(found ~= nil,          "firstId entry not found in GetQueuedActions")
		assert(found.actionType == "SwingIntent", "wrong actionType")
		assert(found.sent       == false,         "expected sent=false")
		assert(type(found.timestamp) == "number", "expected numeric timestamp")
	end)

	-- 10 ───────────────────────────────────────────────────────────────────
	check("CAC: GetQueuedActions() returns copy — mutating it does not affect state", function()
		local copy1 = CAC:GetQueuedActions()
		for _, entry in ipairs(copy1) do
			entry.actionType = "MUTATED"
			entry.sent       = true
		end
		local copy2 = CAC:GetQueuedActions()
		for _, entry in ipairs(copy2) do
			assert(entry.actionType ~= "MUTATED",
				"internal entry was mutated via returned copy")
			assert(entry.sent == false,
				"internal sent flag was mutated via returned copy")
		end
	end)

	-- 11 ───────────────────────────────────────────────────────────────────
	check("CAC: IsActionSent returns false before MarkActionSent", function()
		assert(CAC:IsActionSent(firstId) == false,
			"expected sent=false before MarkActionSent")
	end)

	-- 12 ───────────────────────────────────────────────────────────────────
	check("CAC: MarkActionSent → IsActionSent returns true", function()
		CAC:MarkActionSent(firstId)
		assert(CAC:IsActionSent(firstId) == true,
			"expected sent=true after MarkActionSent")
	end)

	-- 13 ───────────────────────────────────────────────────────────────────
	check("CAC: MarkActionSent with unknown ID warns without crash", function()
		CAC:MarkActionSent("nonexistent_action_id_xyz")
		-- No assert needed — pcall in check() catches crashes
	end)

	-- 14 ───────────────────────────────────────────────────────────────────
	check("CAC: IsActionSent for unknown ID returns false", function()
		assert(CAC:IsActionSent("nonexistent_xyz") == false,
			"expected false for unknown actionId")
	end)

	-- 15 ───────────────────────────────────────────────────────────────────
	check("CAC: ClearActions() resets count to 0", function()
		CAC:ClearActions()
		assert(CAC:GetActionCount() == 0,
			("expected 0 after ClearActions, got %d"):format(CAC:GetActionCount()))
		assert(#CAC:GetQueuedActions() == 0, "expected empty array after ClearActions")
	end)

	-- 16 ───────────────────────────────────────────────────────────────────
	check("CAC: Destroy() resets state and counter", function()
		CAC:QueueAction("SetReady", {})   -- add one before destroy
		CAC:Destroy()
		assert(CAC:GetActionCount() == 0,  "expected 0 after Destroy")
	end)

	-- Restore and verify counter resets
	CAC:Init()

	-- 17 ───────────────────────────────────────────────────────────────────
	check("CAC: action IDs restart from 1 after Destroy+Init", function()
		local id = CAC:QueueAction("OpenShop", {})
		assert(id == "action_1",
			("expected 'action_1' after re-init, got %q"):format(tostring(id)))
		CAC:ClearActions()
	end)

end -- cacOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 2 — RequestControllerModule  (checks 18–25)
-- ════════════════════════════════════════════════════════════════════════════

local rcOk, rcResult = safeRequire(
	script.Parent.Parent.Modules.RequestControllerModule)

if rcOk then

	local RC: any = rcResult

	-- 18 ───────────────────────────────────────────────────────────────────
	check("RC: module loads successfully", function()
		assert(type(RC) == "table", "expected table, got " .. type(RC))
	end)

	-- 19 ───────────────────────────────────────────────────────────────────
	check("RC: GetRequestCount() is 0 initially", function()
		assert(RC:GetRequestCount() == 0,
			("expected 0, got %d"):format(RC:GetRequestCount()))
	end)

	-- 20 ───────────────────────────────────────────────────────────────────
	check("RC: SendRequest with empty name is rejected, count unchanged", function()
		RC:SendRequest("", {})
		assert(RC:GetRequestCount() == 0,
			"empty name must not increment request count")
	end)

	-- 21 ───────────────────────────────────────────────────────────────────
	-- Use a name that NCM does not know — it will warn-and-no-op.
	-- This verifies the count increments without firing a real remote.
	check("RC: SendRequest with valid name increments count", function()
		RC:SendRequest("Sprint20_TestEvent_DoNotExist", {})
		assert(RC:GetRequestCount() == 1,
			("expected count=1, got %d"):format(RC:GetRequestCount()))
	end)

	-- 22 ───────────────────────────────────────────────────────────────────
	check("RC: InvokeRequest with empty name is rejected, count unchanged", function()
		local before = RC:GetRequestCount()
		RC:InvokeRequest("", {})
		assert(RC:GetRequestCount() == before,
			"empty name must not increment request count")
	end)

	-- 23 ───────────────────────────────────────────────────────────────────
	check("RC: InvokeRequest with valid name increments count", function()
		RC:InvokeRequest("Sprint20_TestFunc_DoNotExist", {})
		assert(RC:GetRequestCount() == 2,
			("expected count=2, got %d"):format(RC:GetRequestCount()))
	end)

	-- 24 ───────────────────────────────────────────────────────────────────
	check("RC: ResetRequestCount() resets to 0", function()
		RC:ResetRequestCount()
		assert(RC:GetRequestCount() == 0,
			("expected 0 after reset, got %d"):format(RC:GetRequestCount()))
	end)

	-- 25 ───────────────────────────────────────────────────────────────────
	check("RC: Destroy() resets count", function()
		RC:SendRequest("Sprint20_TestEvent_DoNotExist", {})
		RC:Destroy()
		assert(RC:GetRequestCount() == 0,
			"expected count=0 after Destroy")
	end)

	-- Restore
	RC:Init()

	-- 26 ───────────────────────────────────────────────────────────────────
	check("RC: GetRequestCount works after Init restore", function()
		assert(RC:GetRequestCount() == 0,
			"expected 0 after re-init")
	end)

end -- rcOk

-- ════════════════════════════════════════════════════════════════════════════
-- Section 3 — ServerAckControllerModule  (checks 27–40)
-- ════════════════════════════════════════════════════════════════════════════

local sacOk, sacResult = safeRequire(
	script.Parent.Parent.Modules.ServerAckControllerModule)

if sacOk then

	local SAC: any = sacResult

	-- 27 ───────────────────────────────────────────────────────────────────
	check("SAC: module loads successfully", function()
		assert(type(SAC) == "table", "expected table, got " .. type(SAC))
	end)

	-- 28 ───────────────────────────────────────────────────────────────────
	check("SAC: GetPendingCount() is 0 initially", function()
		assert(SAC:GetPendingCount() == 0,
			("expected 0, got %d"):format(SAC:GetPendingCount()))
	end)

	-- 29 ───────────────────────────────────────────────────────────────────
	check("SAC: GetAck for unknown requestId returns nil", function()
		assert(SAC:GetAck("unknown_req") == nil,
			"expected nil for unknown requestId")
	end)

	-- 30 ───────────────────────────────────────────────────────────────────
	check("SAC: TrackRequest adds a Pending entry", function()
		SAC:TrackRequest("req1", "SwingIntent")
		assert(SAC:GetPendingCount() == 1,
			("expected 1 pending, got %d"):format(SAC:GetPendingCount()))
		local ack = SAC:GetAck("req1")
		assert(ack ~= nil,               "expected ack entry for req1")
		assert(ack.status      == "Pending",     "expected status=Pending")
		assert(ack.requestType == "SwingIntent", "expected requestType=SwingIntent")
		assert(ack.receivedAt  == nil,           "expected receivedAt=nil for new request")
	end)

	-- 31 ───────────────────────────────────────────────────────────────────
	check("SAC: ReceiveAck Accepted updates status and payload", function()
		SAC:ReceiveAck("req1", "Accepted", { score = 5 })
		local ack = SAC:GetAck("req1")
		assert(ack ~= nil,                       "expected ack entry")
		assert(ack.status     == "Accepted",     "expected Accepted status")
		assert(ack.payload    ~= nil,            "expected payload set")
		assert(ack.receivedAt ~= nil,            "expected receivedAt set")
	end)

	-- 32 ───────────────────────────────────────────────────────────────────
	check("SAC: GetPendingCount drops to 0 after Accepted", function()
		assert(SAC:GetPendingCount() == 0,
			("expected 0 after Accepted, got %d"):format(SAC:GetPendingCount()))
	end)

	-- 33 ───────────────────────────────────────────────────────────────────
	check("SAC: ReceiveAck Rejected status", function()
		SAC:TrackRequest("req2", "HoleReady")
		SAC:ReceiveAck("req2", "Rejected", { reason = "tooLate" })
		local ack = SAC:GetAck("req2")
		assert(ack ~= nil,               "expected ack entry for req2")
		assert(ack.status == "Rejected", "expected Rejected status")
	end)

	-- 34 ───────────────────────────────────────────────────────────────────
	check("SAC: ReceiveAck Timeout status", function()
		SAC:TrackRequest("req3", "QueueMatchmaking")
		SAC:ReceiveAck("req3", "Timeout", nil)
		local ack = SAC:GetAck("req3")
		assert(ack ~= nil,              "expected ack entry for req3")
		assert(ack.status == "Timeout", "expected Timeout status")
	end)

	-- 35 ───────────────────────────────────────────────────────────────────
	check("SAC: ReceiveAck with invalid status warns, status unchanged", function()
		SAC:TrackRequest("req4", "SetReady")
		SAC:ReceiveAck("req4", "INVALID_STATUS_XYZ", {})
		local ack = SAC:GetAck("req4")
		assert(ack ~= nil,               "expected ack entry for req4")
		assert(ack.status == "Pending",  "status must remain Pending after invalid ReceiveAck")
	end)

	-- 36 ───────────────────────────────────────────────────────────────────
	check("SAC: ReceiveAck for unknown requestId warns without crash", function()
		SAC:ReceiveAck("totally_unknown_req", "Accepted", {})
		-- No assert — pcall in check() catches crashes
	end)

	-- 37 ───────────────────────────────────────────────────────────────────
	check("SAC: GetPendingCount reflects only Pending entries", function()
		-- req1=Accepted, req2=Rejected, req3=Timeout, req4=Pending
		assert(SAC:GetPendingCount() == 1,
			("expected 1 pending (req4), got %d"):format(SAC:GetPendingCount()))
	end)

	-- 38 ───────────────────────────────────────────────────────────────────
	check("SAC: GetAck returns copy — mutating it does not affect internal state", function()
		local copy = SAC:GetAck("req1")
		assert(copy ~= nil, "expected ack copy")
		local copyCasted = copy :: any
		copyCasted.status      = "MUTATED"
		copyCasted.requestType = "MUTATED"
		local fresh = SAC:GetAck("req1")
		local freshCasted = fresh :: any
		assert(freshCasted.status      == "Accepted",  "status was mutated through copy")
		assert(freshCasted.requestType == "SwingIntent", "requestType was mutated through copy")
	end)

	-- 39 ───────────────────────────────────────────────────────────────────
	check("SAC: ClearAcks() removes all tracked entries", function()
		SAC:ClearAcks()
		assert(SAC:GetPendingCount() == 0,    "expected 0 pending after ClearAcks")
		assert(SAC:GetAck("req1")    == nil,  "expected nil GetAck after ClearAcks")
	end)

	-- 40 ───────────────────────────────────────────────────────────────────
	check("SAC: Destroy() resets all state", function()
		SAC:TrackRequest("reqBeforeDestroy", "SwingIntent")
		SAC:Destroy()
		assert(SAC:GetPendingCount()             == 0,   "expected 0 after Destroy")
		assert(SAC:GetAck("reqBeforeDestroy")    == nil, "expected nil GetAck after Destroy")
	end)

	-- Restore
	SAC:Init()

	-- 41 ───────────────────────────────────────────────────────────────────
	check("SAC: TrackRequest and ReceiveAck work after Init restore", function()
		SAC:TrackRequest("reqAfterRestore", "OpenShop")
		assert(SAC:GetPendingCount() == 1, "expected 1 pending after re-init")
		SAC:ReceiveAck("reqAfterRestore", "Accepted", {})
		assert(SAC:GetPendingCount() == 0, "expected 0 after Accepted")
		SAC:ClearAcks()
	end)

end -- sacOk

-- ════════════════════════════════════════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════════════════════════════════════════

print(TAG .. " ─────────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 20 client smoke tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end
