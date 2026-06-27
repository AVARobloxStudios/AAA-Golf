--!strict
return function()
-- Sprint27ClientTest — ModuleScript
-- Client smoke tests for Sprint 27: RoundPipelineClientControllerModule.
-- Run via TestRunner.client.lua; output appears in Studio Output.
--
-- Covers (18 checks):
--   RPCC — module loading, all public methods exist, Init state,
--     PrepareHole queues HoleReady (duplicate prevention via GPIC),
--     SubmitSwing queues SwingIntent (duplicate prevention via GPIC),
--     DispatchQueuedActions dispatches via CAIC, GetLastQueuedCount,
--     GetLastDispatchCount, Reset (clears counters + GPIC cycle guards),
--     Update, Destroy, re-Init recovery.
--
-- Dependencies GPIC, GABC, CAC, CAIC are reset for isolation.
-- CAIC requires ADC (initialized by its thin runner) — ADC is not destroyed.

print("[Sprint27ClientTest] Script started")

local TAG    = "[Sprint27ClientTest]"
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

-- ── Requires ──────────────────────────────────────────────────────────────────

local RPCC: any = require(script.Parent.Parent.Modules.RoundPipelineClientControllerModule)
local GPIC: any = require(script.Parent.Parent.Modules.GameplayPipelineIntegrationControllerModule)
local CAC:  any = require(script.Parent.Parent.Modules.ClientActionControllerModule)
local CAIC: any = require(script.Parent.Parent.Modules.ClientAckIntegrationControllerModule)
local GABC: any = require(script.Parent.Parent.Modules.GameplayActionBridgeControllerModule)

-- ── Test isolation ─────────────────────────────────────────────────────────────
-- Destroy in dependency order so re-Init is clean.

RPCC:Destroy()
GPIC:Destroy()
GABC:Destroy()
CAIC:Destroy()
CAC:Destroy()

CAC:Init()
GABC:Init()
CAIC:Init()
GPIC:Init()
RPCC:Init()

-- ── Module loading ────────────────────────────────────────────────────────────

check("RPCC: module loads", function()
	assert(type(RPCC) == "table", "expected table")
end)

check("RPCC: all public methods exist", function()
	local methods = {
		"Init", "Update", "Destroy",
		"PrepareHole", "SubmitSwing", "DispatchQueuedActions",
		"GetLastQueuedCount", "GetLastDispatchCount", "Reset",
	}
	for _, name in ipairs(methods) do
		assert(type(RPCC[name]) == "function",
			("expected function for %q"):format(name))
	end
end)

-- ── Init state ────────────────────────────────────────────────────────────────

check("RPCC: GetLastQueuedCount = 0 after Init", function()
	assert(RPCC:GetLastQueuedCount() == 0,
		("expected 0, got %d"):format(RPCC:GetLastQueuedCount()))
end)

check("RPCC: GetLastDispatchCount = 0 after Init", function()
	assert(RPCC:GetLastDispatchCount() == 0,
		("expected 0, got %d"):format(RPCC:GetLastDispatchCount()))
end)

-- ── PrepareHole ───────────────────────────────────────────────────────────────

check("RPCC: PrepareHole queues HoleReady in CAC, GetLastQueuedCount = 1", function()
	CAC:ClearActions()
	GPIC:Reset()
	RPCC:PrepareHole()
	assert(CAC:GetActionCount() == 1,
		("expected 1 action in CAC, got %d"):format(CAC:GetActionCount()))
	assert(RPCC:GetLastQueuedCount() == 1,
		("expected GetLastQueuedCount=1, got %d"):format(RPCC:GetLastQueuedCount()))
end)

check("RPCC: duplicate PrepareHole is prevented (GPIC guard), count stays 1", function()
	RPCC:PrepareHole()   -- GPIC guard → no-op
	assert(RPCC:GetLastQueuedCount() == 1,
		("expected 1 after duplicate, got %d"):format(RPCC:GetLastQueuedCount()))
	assert(CAC:GetActionCount() == 1,
		("expected 1 action in CAC after duplicate, got %d"):format(CAC:GetActionCount()))
end)

-- ── SubmitSwing ───────────────────────────────────────────────────────────────

check("RPCC: SubmitSwing queues SwingIntent, GetLastQueuedCount = 2", function()
	RPCC:SubmitSwing({ aimVector = Vector3.new(0, 0, -1), power = 0.75 })
	assert(RPCC:GetLastQueuedCount() == 2,
		("expected GetLastQueuedCount=2, got %d"):format(RPCC:GetLastQueuedCount()))
	assert(CAC:GetActionCount() == 2,
		("expected 2 actions in CAC, got %d"):format(CAC:GetActionCount()))
end)

check("RPCC: duplicate SubmitSwing is prevented, count stays 2", function()
	RPCC:SubmitSwing({ aimVector = Vector3.new(1, 0, 0), power = 0.5 })
	assert(RPCC:GetLastQueuedCount() == 2,
		("expected 2 after duplicate, got %d"):format(RPCC:GetLastQueuedCount()))
	assert(CAC:GetActionCount() == 2,
		("expected 2 actions in CAC after duplicate, got %d"):format(CAC:GetActionCount()))
end)

-- ── DispatchQueuedActions ────────────────────────────────────────────────────

check("RPCC: DispatchQueuedActions dispatches 2 queued actions, GetLastDispatchCount = 2", function()
	-- CAC has 2 unsent actions (HoleReady + SwingIntent from above).
	RPCC:DispatchQueuedActions()
	assert(RPCC:GetLastDispatchCount() == 2,
		("expected GetLastDispatchCount=2, got %d"):format(RPCC:GetLastDispatchCount()))
end)

check("RPCC: second DispatchQueuedActions finds no unsent actions → GetLastDispatchCount = 0", function()
	RPCC:DispatchQueuedActions()
	assert(RPCC:GetLastDispatchCount() == 0,
		("expected 0 for empty unsent queue, got %d"):format(RPCC:GetLastDispatchCount()))
end)

-- ── Reset ─────────────────────────────────────────────────────────────────────

check("RPCC: Reset clears local counters", function()
	RPCC:Reset()
	assert(RPCC:GetLastQueuedCount()   == 0,
		("expected GetLastQueuedCount=0 after Reset, got %d"):format(
			RPCC:GetLastQueuedCount()))
	assert(RPCC:GetLastDispatchCount() == 0,
		("expected GetLastDispatchCount=0 after Reset, got %d"):format(
			RPCC:GetLastDispatchCount()))
end)

check("RPCC: PrepareHole works again after Reset (GPIC guards cleared)", function()
	CAC:ClearActions()
	RPCC:PrepareHole()
	assert(RPCC:GetLastQueuedCount() == 1,
		("expected GetLastQueuedCount=1 after Reset+PrepareHole, got %d"):format(
			RPCC:GetLastQueuedCount()))
	assert(CAC:GetActionCount() == 1,
		("expected 1 action in CAC after Reset+PrepareHole, got %d"):format(
			CAC:GetActionCount()))
end)

-- ── Update ────────────────────────────────────────────────────────────────────

check("RPCC: Update(0) does not error", function()
	RPCC:Update(0)
end)

-- ── Destroy + re-Init ─────────────────────────────────────────────────────────

check("RPCC: PrepareHole after Destroy is a no-op (_initialized = false)", function()
	RPCC:Destroy()
	CAC:ClearActions()
	GPIC:Reset()
	RPCC:PrepareHole()   -- _initialized = false → no-op
	assert(CAC:GetActionCount() == 0,
		("expected 0 actions in CAC after post-Destroy PrepareHole, got %d"):format(
			CAC:GetActionCount()))
	assert(RPCC:GetLastQueuedCount() == 0,
		"expected GetLastQueuedCount=0 after post-Destroy PrepareHole")
end)

check("RPCC: re-Init after Destroy works — counts reset to 0", function()
	RPCC:Init()
	assert(RPCC:GetLastQueuedCount()   == 0, "expected GetLastQueuedCount=0 after re-Init")
	assert(RPCC:GetLastDispatchCount() == 0, "expected GetLastDispatchCount=0 after re-Init")
end)

check("RPCC: PrepareHole works after re-Init", function()
	CAC:ClearActions()
	GPIC:Reset()
	RPCC:PrepareHole()
	assert(RPCC:GetLastQueuedCount() == 1,
		("expected GetLastQueuedCount=1 after re-Init PrepareHole, got %d"):format(
			RPCC:GetLastQueuedCount()))
end)

-- ── Teardown ──────────────────────────────────────────────────────────────────

RPCC:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

print(TAG .. " ──────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 27 client tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end

end
