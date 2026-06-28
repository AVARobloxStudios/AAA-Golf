--!strict
-- PlayableHoleController — LocalScript thin runner (Sprint 33)
-- All logic lives in PlayableHoleControllerModule so it can be required
-- and tested independently by Sprint33ClientTest.

local PlayableHoleControllerModule =
	require(script.Parent.Parent.Modules.PlayableHoleControllerModule)

PlayableHoleControllerModule:Init()

-- If tests run (RUN_LATEST_CLIENT_TEST = true), Sprint35ClientTest calls
-- PHCM:Destroy() on this same singleton (Roblox shares module cache per client).
-- Re-initialize after 8 s — enough for all synchronous tests to complete.
task.delay(8, function()
	if not PlayableHoleControllerModule:IsInitialized() then
		warn("[PlayableHoleController] PHCM torn down by TestRunner — re-initializing")
		PlayableHoleControllerModule:Init()
	end
end)
