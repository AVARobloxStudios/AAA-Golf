--!strict
return function()
-- Sprint26ClientTest
-- Tests for GameplayPipelineIntegrationControllerModule (Sprint 26).
-- Run via TestRunner.client.lua in Studio Play Solo mode.
--
-- Covers (25 checks):
--   Module loading + public API surface
--   Init state, IsReady, GetQueuedCount
--   Bridge registration in ControllerBridgeController
--   QueueHoleReady: queues once, duplicate prevention
--   QueueSwingIntent: queues once, duplicate prevention, invalid payload
--   Reset: clears duplicate guards and count
--   Update does not error
--   Destroy → IsReady=false, post-Destroy calls are no-ops
--   re-Init recovery

local GPIC = require(script.Parent.Parent.Modules.GameplayPipelineIntegrationControllerModule)
local GABC = require(script.Parent.Parent.Modules.GameplayActionBridgeControllerModule)
local CAC  = require(script.Parent.Parent.Modules.ClientActionControllerModule)
local CBC  = require(script.Parent.Parent.Modules.ControllerBridgeControllerModule)

local TAG    = "[Sprint26ClientTest]"
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

-- ── Test isolation ─────────────────────────────────────────────────────────────

GPIC:Destroy()
GABC:Destroy()
CAC:Destroy()

CAC:Init()
GABC:Init()
GPIC:Init()

-- ── Module loading ────────────────────────────────────────────────────────────

check("GPIC: module loads", function()
	assert(type(GPIC) == "table", "expected table")
end)

check("GPIC: Init function exists", function()
	assert(type(GPIC.Init) == "function")
end)

check("GPIC: Destroy function exists", function()
	assert(type(GPIC.Destroy) == "function")
end)

check("GPIC: QueueHoleReady function exists", function()
	assert(type(GPIC.QueueHoleReady) == "function")
end)

check("GPIC: QueueSwingIntent function exists", function()
	assert(type(GPIC.QueueSwingIntent) == "function")
end)

check("GPIC: GetQueuedCount function exists", function()
	assert(type(GPIC.GetQueuedCount) == "function")
end)

check("GPIC: Reset function exists", function()
	assert(type(GPIC.Reset) == "function")
end)

check("GPIC: IsReady function exists", function()
	assert(type(GPIC.IsReady) == "function")
end)

-- ── Init state ────────────────────────────────────────────────────────────────

check("GPIC: IsReady = true after Init", function()
	assert(GPIC:IsReady() == true, "expected IsReady=true after Init")
end)

check("GPIC: GetQueuedCount = 0 after Init", function()
	assert(GPIC:GetQueuedCount() == 0,
		("expected 0, got %d"):format(GPIC:GetQueuedCount()))
end)

-- ── Bridge registration ───────────────────────────────────────────────────────

check("GPIC: GameplayPipeline.QueueHoleReady bridge routes through CBC", function()
	CAC:ClearActions()
	GPIC:Reset()
	local before = CAC:GetActionCount()
	CBC:RunBridge("GameplayPipeline.QueueHoleReady", {})
	assert(CAC:GetActionCount() == before + 1,
		("expected %d actions in CAC, got %d"):format(before + 1, CAC:GetActionCount()))
	GPIC:Reset()
	CAC:ClearActions()
end)

check("GPIC: GameplayPipeline.QueueSwingIntent bridge routes through CBC", function()
	CAC:ClearActions()
	GPIC:Reset()
	local before  = CAC:GetActionCount()
	local payload = { aimVector = Vector3.new(0, 0, -1), power = 0.5 }
	CBC:RunBridge("GameplayPipeline.QueueSwingIntent", payload)
	assert(CAC:GetActionCount() == before + 1,
		("expected %d actions in CAC, got %d"):format(before + 1, CAC:GetActionCount()))
	GPIC:Reset()
	CAC:ClearActions()
end)

-- ── QueueHoleReady ────────────────────────────────────────────────────────────

check("GPIC: QueueHoleReady queues one HoleReady action in CAC", function()
	GPIC:Reset()
	CAC:ClearActions()
	GPIC:QueueHoleReady()
	assert(CAC:GetActionCount() == 1,
		("expected 1 action, got %d"):format(CAC:GetActionCount()))
end)

check("GPIC: GetQueuedCount = 1 after QueueHoleReady", function()
	assert(GPIC:GetQueuedCount() == 1,
		("expected 1, got %d"):format(GPIC:GetQueuedCount()))
end)

check("GPIC: duplicate QueueHoleReady is prevented (count stays 1)", function()
	GPIC:QueueHoleReady()   -- second call — should be no-op
	assert(GPIC:GetQueuedCount() == 1,
		("expected 1 after duplicate, got %d"):format(GPIC:GetQueuedCount()))
	assert(CAC:GetActionCount() == 1,
		("expected 1 action in CAC after duplicate, got %d"):format(CAC:GetActionCount()))
end)

-- ── QueueSwingIntent ──────────────────────────────────────────────────────────

check("GPIC: QueueSwingIntent queues one SwingIntent (total queued = 2)", function()
	GPIC:QueueSwingIntent({ aimVector = Vector3.new(0, 0, -1), power = 0.75 })
	assert(GPIC:GetQueuedCount() == 2,
		("expected 2, got %d"):format(GPIC:GetQueuedCount()))
	assert(CAC:GetActionCount() == 2,
		("expected 2 actions in CAC, got %d"):format(CAC:GetActionCount()))
end)

check("GPIC: duplicate QueueSwingIntent is prevented (count stays 2)", function()
	GPIC:QueueSwingIntent({ aimVector = Vector3.new(1, 0, 0), power = 0.5 })
	assert(GPIC:GetQueuedCount() == 2,
		("expected 2 after duplicate, got %d"):format(GPIC:GetQueuedCount()))
	assert(CAC:GetActionCount() == 2,
		("expected 2 actions in CAC after duplicate, got %d"):format(CAC:GetActionCount()))
end)

-- ── Invalid payload ───────────────────────────────────────────────────────────

check("GPIC: QueueSwingIntent with non-table payload is rejected", function()
	GPIC:Reset()
	CAC:ClearActions()
	GPIC:QueueSwingIntent("not a table" :: any)
	assert(GPIC:GetQueuedCount() == 0,
		("expected 0 after rejected payload, got %d"):format(GPIC:GetQueuedCount()))
	assert(CAC:GetActionCount() == 0,
		("expected 0 actions in CAC, got %d"):format(CAC:GetActionCount()))
end)

-- ── Reset ─────────────────────────────────────────────────────────────────────

check("GPIC: Reset clears duplicate guards so QueueHoleReady can fire again", function()
	-- Ensure HoleReady is already guarded.
	GPIC:QueueHoleReady()
	assert(GPIC:GetQueuedCount() == 1, "pre-condition: HoleReady queued once")

	GPIC:Reset()
	assert(GPIC:GetQueuedCount() == 0, "expected count=0 after Reset")

	-- Now it should be allowed again.
	CAC:ClearActions()
	GPIC:QueueHoleReady()
	assert(GPIC:GetQueuedCount() == 1, "expected 1 after Reset + QueueHoleReady")
	assert(CAC:GetActionCount() == 1, "expected 1 action in CAC after Reset + QueueHoleReady")
end)

-- ── Update ────────────────────────────────────────────────────────────────────

check("GPIC: Update(0) does not error", function()
	GPIC:Update(0)
end)

-- ── Destroy + re-Init ─────────────────────────────────────────────────────────

check("GPIC: IsReady = false after Destroy", function()
	GPIC:Destroy()
	assert(GPIC:IsReady() == false, "expected IsReady=false after Destroy")
end)

check("GPIC: QueueHoleReady after Destroy is a no-op", function()
	CAC:ClearActions()
	GPIC:QueueHoleReady()   -- _initialized = false → should no-op
	assert(CAC:GetActionCount() == 0,
		("expected 0 actions in CAC after post-Destroy call, got %d"):format(
			CAC:GetActionCount()))
end)

check("GPIC: re-Init after Destroy works — IsReady=true, count=0", function()
	GPIC:Init()
	assert(GPIC:IsReady() == true, "expected IsReady=true after re-Init")
	assert(GPIC:GetQueuedCount() == 0, "expected count=0 after re-Init")
end)

check("GPIC: QueueHoleReady works after re-Init", function()
	CAC:ClearActions()
	GPIC:QueueHoleReady()
	assert(GPIC:GetQueuedCount() == 1, "expected GetQueuedCount=1 after re-Init QueueHoleReady")
	assert(CAC:GetActionCount() == 1, "expected 1 action in CAC after re-Init")
end)

-- ── Teardown ───────────────────────────────────────────────────────────────────

GPIC:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

print(TAG .. " ──────────────────────────────────────────────────────────")
print(TAG .. (" Results: %d passed, %d failed"):format(passed, failed))
if failed == 0 then
	print(TAG .. " All Sprint 26 client tests PASSED.")
else
	warn(TAG .. (" %d test(s) FAILED — see warnings above."):format(failed))
end

end
