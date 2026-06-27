--!strict
-- Sprint23ServerTest — Server Script smoke tests for Sprint 23.
-- Run in Studio Play Solo mode. No API Services required.
-- No DataStore, no real gameplay, no real client response required.
--
-- Covers (35 checks):
--   RequestProcessorService  — module loading, Init, validation, pipeline,
--                              processedCount, ResetProcessedCount, Destroy
--   ActionExecutionService   — module loading, Init, all 8 eventTypes,
--                              unknown eventType, executionCount, Destroy
--   ResponseDispatchService  — module loading, Init, all 3 ack methods,
--                              DispatchResult mapping, dispatchCount, Destroy
--   Full pipeline            — ProcessRequest drives all three services end-to-end
--   Recovery                 — Destroy() + Init() restores a clean initial state

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RPS = require(ServerScriptService.Services.RequestProcessorService)
local AES = require(ServerScriptService.Services.ActionExecutionService)
local RDS = require(ServerScriptService.Services.ResponseDispatchService)

local TAG = "[Sprint23ServerTest]"

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

-- ── Immediate module-level checks (no player needed) ─────────────────────────

check("RPS: module loads", function()
	assert(type(RPS) == "table", "expected table")
end)

check("AES: module loads", function()
	assert(type(AES) == "table", "expected table")
end)

check("RDS: module loads", function()
	assert(type(RDS) == "table", "expected table")
end)

check("RPS: Init function exists", function()
	assert(type(RPS.Init) == "function")
end)

check("AES: Init function exists", function()
	assert(type(AES.Init) == "function")
end)

check("RDS: Init function exists", function()
	assert(type(RDS.Init) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 23 service tests for " .. player.Name .. " ──")

	-- Reset all three services for test isolation.
	-- Destroy is idempotent even before first Init.
	RPS:Destroy()
	AES:Destroy()
	RDS:Destroy()
	AES:Init({})
	RDS:Init({})
	RPS:Init({})

	-- ── Init guard ─────────────────────────────────────────────────────────────

	check("RPS: Init called twice warns and skips", function()
		RPS:Init({})   -- second call; should warn and no-op
		assert(RPS:GetProcessedCount() == 0, "count should still be 0 after double Init")
	end)

	check("AES: Init called twice warns and skips", function()
		AES:Init({})
		assert(AES:GetExecutionCount() == 0, "count should still be 0 after double Init")
	end)

	check("RDS: Init called twice warns and skips", function()
		RDS:Init({})
		assert(RDS:GetDispatchCount() == 0, "count should still be 0 after double Init")
	end)

	-- ── ActionExecutionService ────────────────────────────────────────────────

	check("AES: GetExecutionCount() is 0 initially", function()
		assert(AES:GetExecutionCount() == 0,
			("expected 0, got %d"):format(AES:GetExecutionCount()))
	end)

	-- All 8 known eventTypes return success without crashing.
	local KNOWN_EVENTS = {
		"SwingIntent", "HoleReady", "QueueMatchmaking", "CancelMatchmaking",
		"SetReady", "OpenShop", "PreviewItem", "EquipCosmetic",
	}

	check("AES: all 8 known eventTypes execute without error", function()
		for _, et in ipairs(KNOWN_EVENTS) do
			local result = AES:Execute(player, { eventType = et, payload = {} })
			assert(type(result) == "table",
				("expected table result for %q"):format(et))
			assert(result.success == true,
				("expected success=true for %q, got %s"):format(et, tostring(result.success)))
		end
	end)

	check("AES: executionCount = 8 after executing all known eventTypes", function()
		assert(AES:GetExecutionCount() == 8,
			("expected 8, got %d"):format(AES:GetExecutionCount()))
	end)

	check("AES: known eventType returns success envelope", function()
		AES:ResetExecutionCount()
		local result = AES:Execute(player, { eventType = "HoleReady", payload = {} })
		assert(result.success == true, "expected success=true")
		assert(type(result.status) == "string" and result.status ~= "",
			"expected non-empty status string")
	end)

	check("AES: executionCount increments for known eventType", function()
		assert(AES:GetExecutionCount() == 1,
			("expected 1, got %d"):format(AES:GetExecutionCount()))
	end)

	check("AES: unknown eventType returns failure envelope without crashing", function()
		local countBefore = AES:GetExecutionCount()
		local result = AES:Execute(player, { eventType = "TOTALLY_UNKNOWN", payload = {} })
		assert(type(result) == "table", "expected table result for unknown eventType")
		assert(result.success == false,
			("expected success=false for unknown eventType, got %s"):format(
				tostring(result.success)))
		assert(result.status == "UnknownEvent",
			("expected status='UnknownEvent', got %q"):format(tostring(result.status)))
		assert(AES:GetExecutionCount() == countBefore,
			"executionCount must not increment for unknown eventType")
	end)

	check("AES: ResetExecutionCount resets to 0", function()
		AES:ResetExecutionCount()
		assert(AES:GetExecutionCount() == 0,
			("expected 0, got %d"):format(AES:GetExecutionCount()))
	end)

	-- ── ResponseDispatchService ───────────────────────────────────────────────

	check("RDS: GetDispatchCount() is 0 initially", function()
		assert(RDS:GetDispatchCount() == 0,
			("expected 0, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RDS: DispatchRequestAck increments dispatchCount", function()
		RDS:ResetDispatchCount()
		RDS:DispatchRequestAck(player, "req_001", "Accepted", nil)
		assert(RDS:GetDispatchCount() == 1,
			("expected 1, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RDS: DispatchActionAck increments dispatchCount", function()
		RDS:DispatchActionAck(player, "action_001", "Accepted", nil)
		assert(RDS:GetDispatchCount() == 2,
			("expected 2, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RDS: DispatchServerAck increments dispatchCount", function()
		RDS:DispatchServerAck(player, "req_002", "Accepted", nil)
		assert(RDS:GetDispatchCount() == 3,
			("expected 3, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RDS: DispatchResult (success) fires ActionAck and increments count", function()
		local before = RDS:GetDispatchCount()
		RDS:DispatchResult(player, "action_002",
			{ success = true, status = "SwingQueued", payload = nil })
		assert(RDS:GetDispatchCount() == before + 1,
			("expected %d, got %d"):format(before + 1, RDS:GetDispatchCount()))
	end)

	check("RDS: DispatchResult (failure) fires ActionAck and increments count", function()
		local before = RDS:GetDispatchCount()
		RDS:DispatchResult(player, "action_003",
			{ success = false, status = "HandlerError", payload = nil })
		assert(RDS:GetDispatchCount() == before + 1,
			("expected %d, got %d"):format(before + 1, RDS:GetDispatchCount()))
	end)

	check("RDS: ResetDispatchCount resets to 0", function()
		RDS:ResetDispatchCount()
		assert(RDS:GetDispatchCount() == 0,
			("expected 0, got %d"):format(RDS:GetDispatchCount()))
	end)

	-- ── RequestProcessorService ───────────────────────────────────────────────

	AES:ResetExecutionCount()
	RDS:ResetDispatchCount()

	check("RPS: GetProcessedCount() is 0 initially", function()
		assert(RPS:GetProcessedCount() == 0,
			("expected 0, got %d"):format(RPS:GetProcessedCount()))
	end)

	check("RPS: ProcessRequest with valid envelope returns true", function()
		local ok = RPS:ProcessRequest(player, {
			actionId  = "action_s23_001",
			eventType = "HoleReady",
			payload   = {},
		})
		assert(ok == true, "expected true for valid envelope")
	end)

	check("RPS: processedCount = 1 after one valid request", function()
		assert(RPS:GetProcessedCount() == 1,
			("expected 1, got %d"):format(RPS:GetProcessedCount()))
	end)

	check("RPS: AES.executionCount = 1 after valid ProcessRequest", function()
		assert(AES:GetExecutionCount() == 1,
			("expected 1, got %d"):format(AES:GetExecutionCount()))
	end)

	check("RPS: RDS.dispatchCount = 1 after valid ProcessRequest", function()
		assert(RDS:GetDispatchCount() == 1,
			("expected 1, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RPS: no duplicate execution — one call produces exactly one execution", function()
		assert(AES:GetExecutionCount() == 1,
			("expected exactly 1 execution, got %d"):format(AES:GetExecutionCount()))
		assert(RDS:GetDispatchCount() == 1,
			("expected exactly 1 dispatch, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("RPS: ProcessRequest rejects missing actionId (returns false)", function()
		local before = RPS:GetProcessedCount()
		local ok = RPS:ProcessRequest(player, {
			eventType = "HoleReady",
			payload   = {},
		})
		assert(ok == false, "expected false for missing actionId")
		assert(RPS:GetProcessedCount() == before,
			"processedCount must not increment for malformed envelope")
	end)

	check("RPS: ProcessRequest rejects empty actionId", function()
		local before = RPS:GetProcessedCount()
		local ok = RPS:ProcessRequest(player, {
			actionId  = "",
			eventType = "HoleReady",
			payload   = {},
		})
		assert(ok == false, "expected false for empty actionId")
		assert(RPS:GetProcessedCount() == before,
			"processedCount must not increment for empty actionId")
	end)

	check("RPS: ProcessRequest rejects missing eventType (returns false)", function()
		local before = RPS:GetProcessedCount()
		local ok = RPS:ProcessRequest(player, {
			actionId = "action_s23_002",
			payload  = {},
		})
		assert(ok == false, "expected false for missing eventType")
		assert(RPS:GetProcessedCount() == before,
			"processedCount must not increment for missing eventType")
	end)

	check("RPS: ProcessRequest rejects non-table payload", function()
		local before = RPS:GetProcessedCount()
		local ok = RPS:ProcessRequest(player, {
			actionId  = "action_s23_003",
			eventType = "HoleReady",
			payload   = "not a table",
		})
		assert(ok == false, "expected false for non-table payload")
		assert(RPS:GetProcessedCount() == before,
			"processedCount must not increment for non-table payload")
	end)

	check("RPS: ProcessRequest rejects non-table envelope", function()
		local before = RPS:GetProcessedCount()
		local ok = RPS:ProcessRequest(player, "not a table" :: any)
		assert(ok == false, "expected false for non-table envelope")
		assert(RPS:GetProcessedCount() == before,
			"processedCount must not increment for non-table envelope")
	end)

	check("RPS: ResetProcessedCount resets to 0", function()
		RPS:ResetProcessedCount()
		assert(RPS:GetProcessedCount() == 0,
			("expected 0, got %d"):format(RPS:GetProcessedCount()))
	end)

	-- ── Full pipeline: SwingIntent through all three services ──────────────────

	AES:ResetExecutionCount()
	RDS:ResetDispatchCount()
	RPS:ResetProcessedCount()

	check("Pipeline: SwingIntent flows through RPS → AES → RDS without error", function()
		local ok = RPS:ProcessRequest(player, {
			actionId  = "action_s23_swing",
			eventType = "SwingIntent",
			payload   = { power = 0.75, angle = 10 },
		})
		assert(ok == true, "expected ProcessRequest to return true")
		assert(RPS:GetProcessedCount() == 1, "RPS count should be 1")
		assert(AES:GetExecutionCount() == 1, "AES count should be 1")
		assert(RDS:GetDispatchCount()  == 1, "RDS count should be 1")
	end)

	check("Pipeline: Update(0) on all three services does not error", function()
		RPS:Update(0)
		AES:Update(0)
		RDS:Update(0)
	end)

	-- ── Destroy + Init recovery ───────────────────────────────────────────────

	check("Destroy: resets RPS.processedCount to 0", function()
		RPS:Destroy()
		assert(RPS:GetProcessedCount() == 0,
			("expected 0 after Destroy, got %d"):format(RPS:GetProcessedCount()))
	end)

	check("Destroy: resets AES.executionCount to 0", function()
		AES:Destroy()
		assert(AES:GetExecutionCount() == 0,
			("expected 0 after Destroy, got %d"):format(AES:GetExecutionCount()))
	end)

	check("Destroy: resets RDS.dispatchCount to 0", function()
		RDS:Destroy()
		assert(RDS:GetDispatchCount() == 0,
			("expected 0 after Destroy, got %d"):format(RDS:GetDispatchCount()))
	end)

	check("Recovery: re-Init after Destroy works for all three services", function()
		AES:Init({})
		RDS:Init({})
		RPS:Init({})
		assert(RPS:GetProcessedCount() == 0, "RPS count should be 0 after re-Init")
		assert(AES:GetExecutionCount() == 0, "AES count should be 0 after re-Init")
		assert(RDS:GetDispatchCount()  == 0, "RDS count should be 0 after re-Init")
	end)

	check("Recovery: ProcessRequest works after re-Init", function()
		local ok = RPS:ProcessRequest(player, {
			actionId  = "action_s23_recovery",
			eventType = "SetReady",
			payload   = { isReady = true },
		})
		assert(ok == true, "expected true after re-Init")
		assert(RPS:GetProcessedCount() == 1, "RPS count should be 1")
		assert(AES:GetExecutionCount() == 1, "AES count should be 1")
		assert(RDS:GetDispatchCount()  == 1, "RDS count should be 1")
	end)

	-- ── Summary ─────────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 23 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Trigger tests when a player is available ──────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
