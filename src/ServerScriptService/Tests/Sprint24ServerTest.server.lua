--!strict
-- Sprint24ServerTest — Server Script smoke tests for Sprint 24.
-- Run in Studio Play Solo mode. No API Services required.
--
-- Covers (25 checks):
--   ServerActionBridgeService — module loading, Init/Destroy, IsConnected,
--     duplicate-connection guard, valid envelope forwarding, malformed envelope
--     rejection, counter accuracy, ResetCounts, Destroy disconnects, re-Init,
--     _dispatch no-op after Destroy.
--
-- Uses _dispatch() directly (same pattern as Sprint5Test uses EventBusHandler:_dispatch)
-- so no live client is required.  RequestProcessorService is initialized by the
-- test to verify cross-service forwarding.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local SABS = require(ServerScriptService.Services.ServerActionBridgeService)
local RPS  = require(ServerScriptService.Services.RequestProcessorService)
local AES  = require(ServerScriptService.Services.ActionExecutionService)
local RDS  = require(ServerScriptService.Services.ResponseDispatchService)

local TAG = "[Sprint24ServerTest]"

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

check("SABS: module loads", function()
	assert(type(SABS) == "table", "expected table")
end)

check("SABS: Init function exists", function()
	assert(type(SABS.Init) == "function")
end)

check("SABS: Destroy function exists", function()
	assert(type(SABS.Destroy) == "function")
end)

check("SABS: IsConnected function exists", function()
	assert(type(SABS.IsConnected) == "function")
end)

check("SABS: _dispatch function exists", function()
	assert(type(SABS._dispatch) == "function")
end)

-- ── Player-gated tests ────────────────────────────────────────────────────────

local function runTests(player: Player)
	print(TAG .. " ── Sprint 24 service tests for " .. player.Name .. " ──")

	-- Reset all services for test isolation.
	SABS:Destroy()
	RPS:Destroy()
	AES:Destroy()
	RDS:Destroy()

	-- ── IsConnected state before Init ─────────────────────────────────────────

	check("SABS: IsConnected = false before Init", function()
		assert(SABS:IsConnected() == false,
			("expected false, got %s"):format(tostring(SABS:IsConnected())))
	end)

	-- ── Init ─────────────────────────────────────────────────────────────────

	-- Initialize the full Sprint 23 pipeline so forwarded envelopes can be processed.
	AES:Init({})
	RDS:Init({})
	RPS:Init({})
	SABS:Init({})

	check("SABS: IsConnected = true after Init", function()
		assert(SABS:IsConnected() == true,
			("expected true, got %s"):format(tostring(SABS:IsConnected())))
	end)

	check("SABS: Init called twice warns and skips — IsConnected remains true", function()
		SABS:Init({})   -- second call; should warn and no-op
		assert(SABS:IsConnected() == true,
			"IsConnected must still be true after duplicate Init")
	end)

	check("SABS: counts are 0 after Init", function()
		assert(SABS:GetReceivedCount()  == 0, "receivedCount must be 0")
		assert(SABS:GetForwardedCount() == 0, "forwardedCount must be 0")
		assert(SABS:GetRejectedCount()  == 0, "rejectedCount must be 0")
	end)

	-- ── Valid envelope forwarding ─────────────────────────────────────────────

	check("SABS: valid envelope — receivedCount increments", function()
		SABS:_dispatch(player, {
			actionId  = "action_s24_001",
			eventType = "HoleReady",
			payload   = {},
		})
		assert(SABS:GetReceivedCount() == 1,
			("expected 1, got %d"):format(SABS:GetReceivedCount()))
	end)

	check("SABS: valid envelope — forwardedCount increments", function()
		assert(SABS:GetForwardedCount() == 1,
			("expected 1, got %d"):format(SABS:GetForwardedCount()))
	end)

	check("SABS: valid envelope — rejectedCount stays 0", function()
		assert(SABS:GetRejectedCount() == 0,
			("expected 0, got %d"):format(SABS:GetRejectedCount()))
	end)

	check("SABS: valid envelope — RPS.processedCount increments", function()
		assert(RPS:GetProcessedCount() == 1,
			("expected 1, got %d"):format(RPS:GetProcessedCount()))
	end)

	-- ── Malformed envelopes ───────────────────────────────────────────────────

	check("SABS: missing actionId — rejectedCount increments, forwardedCount unchanged", function()
		local fwdBefore = SABS:GetForwardedCount()
		SABS:_dispatch(player, { eventType = "HoleReady", payload = {} })
		assert(SABS:GetRejectedCount() == 1,
			("expected 1, got %d"):format(SABS:GetRejectedCount()))
		assert(SABS:GetForwardedCount() == fwdBefore,
			"forwardedCount must not change for missing actionId")
	end)

	check("SABS: empty actionId — rejectedCount increments", function()
		SABS:_dispatch(player, { actionId = "", eventType = "HoleReady", payload = {} })
		assert(SABS:GetRejectedCount() == 2,
			("expected 2, got %d"):format(SABS:GetRejectedCount()))
	end)

	check("SABS: missing eventType — rejectedCount increments", function()
		SABS:_dispatch(player, { actionId = "action_s24_002", payload = {} })
		assert(SABS:GetRejectedCount() == 3,
			("expected 3, got %d"):format(SABS:GetRejectedCount()))
	end)

	check("SABS: non-table payload — rejectedCount increments", function()
		SABS:_dispatch(player, {
			actionId  = "action_s24_003",
			eventType = "HoleReady",
			payload   = "not a table",
		})
		assert(SABS:GetRejectedCount() == 4,
			("expected 4, got %d"):format(SABS:GetRejectedCount()))
	end)

	check("SABS: non-table envelope — rejectedCount increments", function()
		SABS:_dispatch(player, "not a table" :: any)
		assert(SABS:GetRejectedCount() == 5,
			("expected 5, got %d"):format(SABS:GetRejectedCount()))
	end)

	check("SABS: receivedCount tracks all dispatches (valid + invalid)", function()
		assert(SABS:GetReceivedCount() == 6,
			("expected 6, got %d"):format(SABS:GetReceivedCount()))
	end)

	-- ── ResetCounts ───────────────────────────────────────────────────────────

	check("SABS: ResetCounts resets all counters to 0", function()
		SABS:ResetCounts()
		assert(SABS:GetReceivedCount()  == 0, "receivedCount must be 0")
		assert(SABS:GetForwardedCount() == 0, "forwardedCount must be 0")
		assert(SABS:GetRejectedCount()  == 0, "rejectedCount must be 0")
	end)

	-- ── Destroy ───────────────────────────────────────────────────────────────

	check("SABS: Destroy disconnects (IsConnected = false)", function()
		SABS:Destroy()
		assert(SABS:IsConnected() == false,
			("expected false after Destroy, got %s"):format(tostring(SABS:IsConnected())))
	end)

	check("SABS: Destroy resets counts to 0", function()
		assert(SABS:GetReceivedCount()  == 0, "receivedCount must be 0 after Destroy")
		assert(SABS:GetForwardedCount() == 0, "forwardedCount must be 0 after Destroy")
		assert(SABS:GetRejectedCount()  == 0, "rejectedCount must be 0 after Destroy")
	end)

	check("SABS: _dispatch after Destroy is a no-op (counts do not change)", function()
		local rcvBefore = SABS:GetReceivedCount()
		SABS:_dispatch(player, {
			actionId  = "action_s24_postdestroy",
			eventType = "HoleReady",
			payload   = {},
		})
		assert(SABS:GetReceivedCount() == rcvBefore,
			"receivedCount must not change after Destroy")
	end)

	-- ── re-Init after Destroy ─────────────────────────────────────────────────

	check("SABS: re-Init after Destroy works (IsConnected = true)", function()
		SABS:Init({})
		assert(SABS:IsConnected() == true,
			("expected true after re-Init, got %s"):format(tostring(SABS:IsConnected())))
	end)

	check("SABS: _dispatch works after re-Init", function()
		RPS:Destroy()
		AES:Init({})
		RDS:Init({})
		RPS:Init({})
		SABS:_dispatch(player, {
			actionId  = "action_s24_reinit",
			eventType = "SetReady",
			payload   = { isReady = true },
		})
		assert(SABS:GetForwardedCount() == 1,
			("expected 1 after re-Init dispatch, got %d"):format(SABS:GetForwardedCount()))
		assert(RPS:GetProcessedCount() == 1,
			("expected 1 RPS processed after re-Init, got %d"):format(RPS:GetProcessedCount()))
	end)

	check("SABS: Update(0) does not error", function()
		SABS:Update(0)
	end)

	-- ── Teardown ──────────────────────────────────────────────────────────────
	SABS:Destroy()
	RPS:Destroy()
	AES:Destroy()
	RDS:Destroy()

	-- ── Summary ───────────────────────────────────────────────────────────────

	print(TAG .. " ─────────────────────────────────────────────────────────")
	print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print(TAG .. " All Sprint 24 smoke tests PASSED.")
	else
		warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
	end
end

-- ── Trigger per-player tests ──────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runTests, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(runTests, player)
end
