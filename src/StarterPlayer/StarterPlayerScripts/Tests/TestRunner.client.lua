--!strict
-- TestRunner.client.lua
-- Master client test runner for AAA Golf.
--
-- Sprint test scripts live in this folder as ModuleScripts (*.lua).
-- They do NOT run automatically — only this LocalScript invokes them,
-- so Play sessions stay quiet by default.
--
-- ── How to use ────────────────────────────────────────────────────────────────
--
-- Run only the latest sprint (default):
--   RUN_ALL_CLIENT_TESTS      = false
--   RUN_LATEST_CLIENT_TEST    = true
--   LATEST_CLIENT_SPRINT      = 27    ← bump this each sprint
--
-- Run every sprint (full regression before commit):
--   RUN_ALL_CLIENT_TESTS      = true
--
-- Run specific sprints:
--   RUN_SPECIFIC_CLIENT_SPRINTS = {18, 19, 21}
--
-- Run nothing (silence all tests):
--   RUN_ALL_CLIENT_TESTS      = false
--   RUN_LATEST_CLIENT_TEST    = false
--   RUN_SPECIFIC_CLIENT_SPRINTS = {}
--
-- ── Config ────────────────────────────────────────────────────────────────────

local RUN_ALL_CLIENT_TESTS:           boolean  = false
local RUN_LATEST_CLIENT_TEST:         boolean  = true
local LATEST_CLIENT_SPRINT:           number   = 29    -- ← bump this each sprint
local RUN_SPECIFIC_CLIENT_SPRINTS:    {number} = {}

-- ── Sprint registry ───────────────────────────────────────────────────────────
-- Add a new entry here whenever a sprint's test module is created.

local SPRINT_TESTS: {[number]: () -> ()} = {
	[6]  = require(script.Parent.Sprint6ClientTest),
	[7]  = require(script.Parent.Sprint7ClientTest),
	[8]  = require(script.Parent.Sprint8ClientTest),
	[9]  = require(script.Parent.Sprint9ClientTest),
	[10] = require(script.Parent.Sprint10ClientTest),
	[11] = require(script.Parent.Sprint11ClientTest),
	[12] = require(script.Parent.Sprint12ClientTest),
	[13] = require(script.Parent.Sprint13ClientTest),
	[14] = require(script.Parent.Sprint14ClientTest),
	[15] = require(script.Parent.Sprint15ClientTest),
	[16] = require(script.Parent.Sprint16ClientTest),
	[17] = require(script.Parent.Sprint17ClientTest),
	[18] = require(script.Parent.Sprint18ClientTest),
	[19] = require(script.Parent.Sprint19ClientTest),
	[20] = require(script.Parent.Sprint20ClientTest),
	[21] = require(script.Parent.Sprint21ClientTest),
	[22] = require(script.Parent.Sprint22ClientTest),
	[24] = require(script.Parent.Sprint24ClientTest),
	[26] = require(script.Parent.Sprint26ClientTest),
	[27] = require(script.Parent.Sprint27ClientTest),
	[28] = require(script.Parent.Sprint28ClientTest),
	[29] = require(script.Parent.Sprint29ClientTest),
}

-- ── Determine which sprints to run ────────────────────────────────────────────

local toRun: {number} = {}

if RUN_ALL_CLIENT_TESTS then
	for i = 6, 29 do
		table.insert(toRun, i)
	end
elseif #RUN_SPECIFIC_CLIENT_SPRINTS > 0 then
	toRun = RUN_SPECIFIC_CLIENT_SPRINTS
elseif RUN_LATEST_CLIENT_TEST then
	table.insert(toRun, LATEST_CLIENT_SPRINT)
end

-- ── Run ───────────────────────────────────────────────────────────────────────

local TAG = "[TestRunner]"

if #toRun == 0 then
	print(TAG .. " No client tests configured — set RUN_LATEST_CLIENT_TEST = true to run Sprint " .. LATEST_CLIENT_SPRINT)
else
	local label = RUN_ALL_CLIENT_TESTS and "ALL sprints"
		or (#RUN_SPECIFIC_CLIENT_SPRINTS > 0 and "specific sprints " .. table.concat(RUN_SPECIFIC_CLIENT_SPRINTS, ", "))
		or ("Sprint " .. LATEST_CLIENT_SPRINT .. " only")
	print(TAG .. " Running client tests — " .. tostring(label))

	for _, sprintNum in ipairs(toRun) do
		local fn = SPRINT_TESTS[sprintNum]
		if fn then
			print(TAG .. " ── Sprint " .. sprintNum .. " ──────────────────────────────")
			fn()
		else
			warn(TAG .. " No test registered for Sprint " .. sprintNum)
		end
	end

	print(TAG .. " ── Done ────────────────────────────────────────────────────")
end
