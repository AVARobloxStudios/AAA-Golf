--!strict
-- DataStoreBridge — Server-only ModuleScript
-- Manages ProfileService write cadence: batched dirty queue, 60s heartbeat, FlushNow, BindToClose.
-- TDD §12.2 Write Cadence / §12.3 Crash Safety.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

type Entry = {
	profile: any,
	dirty: boolean,
	lastSave: number,
}

local entries: { [number]: Entry } = {}
local initialized = false

local DataStoreBridge = {}
DataStoreBridge.__index = DataStoreBridge

function DataStoreBridge:Init()
	if initialized then return end
	initialized = true

	-- 60s heartbeat: flush all dirty profiles
	task.spawn(function()
		while true do
			task.wait(Constants.PROFILE_HEARTBEAT_INTERVAL)
			for userId, entry in pairs(entries) do
				if entry.dirty and entry.profile then
					local ok, err = pcall(function()
						entry.profile:Save()
					end)
					if ok then
						entry.dirty = false
						entry.lastSave = os.clock()
					else
						warn("[DataStoreBridge] Heartbeat save failed userId=" .. tostring(userId) .. ": " .. tostring(err))
					end
				end
			end
		end
	end)

	-- BindToClose: sequential flush — do NOT task.spawn (TDD §12.3 critical note)
	game:BindToClose(function()
		for userId, entry in pairs(entries) do
			if entry.profile then
				local ok, err = pcall(function()
					entry.profile:Save()
				end)
				if not ok then
					warn("[DataStoreBridge] BindToClose save failed userId=" .. tostring(userId) .. ": " .. tostring(err))
				end
			end
		end
	end)
end

function DataStoreBridge:Update(_dt: number) end
function DataStoreBridge:Destroy() end

-- Called by PlayerDataService immediately after a profile is successfully loaded.
function DataStoreBridge:Register(userId: number, profile: any)
	entries[userId] = {
		profile  = profile,
		dirty    = false,
		lastSave = os.clock(),
	}
end

-- Called by PlayerDataService in PlayerRemoving after FlushNow.
function DataStoreBridge:Unregister(userId: number)
	entries[userId] = nil
end

-- Mark profile dirty — picked up by the next heartbeat tick.
function DataStoreBridge:QueueWrite(userId: number)
	local entry = entries[userId]
	if entry then
		entry.dirty = true
	end
end

-- Immediate synchronous save (blocks until DataStore call completes).
-- Use for round-end and PlayerRemoving — not in hot paths.
function DataStoreBridge:FlushNow(userId: number)
	local entry = entries[userId]
	if not (entry and entry.profile) then return end
	local ok, err = pcall(function()
		entry.profile:Save()
	end)
	if ok then
		entry.dirty = false
		entry.lastSave = os.clock()
	else
		warn("[DataStoreBridge] FlushNow failed userId=" .. tostring(userId) .. ": " .. tostring(err))
	end
end

-- Flush every registered profile — called by BindToClose and admin shutdown commands.
function DataStoreBridge:FlushAllNow()
	for userId, entry in pairs(entries) do
		if entry.profile then
			local ok, err = pcall(function()
				entry.profile:Save()
			end)
			if ok then
				entry.dirty = false
				entry.lastSave = os.clock()
			else
				warn("[DataStoreBridge] FlushAllNow failed userId=" .. tostring(userId) .. ": " .. tostring(err))
			end
		end
	end
end

return DataStoreBridge
