--!strict
-- ClubManager — Client, Milestone 2 (hotfixed Milestone 2.1)
-- Tracks the active club. Handles Z / X keyboard cycling.
-- Call Init() once from PlayableHoleControllerModule:Init().
-- Call SetLocked(true) during swing/flight to prevent accidental cycling.
-- Call OnChanged(cb) to receive notification whenever the selected club changes.
--
-- Keys:
--   Z = previous club (toward Driver / more distance)
--   X = next club    (toward Putter  / more loft)
-- Mouse wheel is intentionally omitted: Roblox's Follow camera also consumes
-- InputChanged scroll events, making simultaneous camera-zoom + club-cycle unreliable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local ClubData = require(ReplicatedStorage.Shared.Modules.ClubData)

local ClubManager = {}

local _initialized: boolean = false

-- Ordered sequence: longest-to-shortest (Driver → Putter), matching how a golf bag is arranged.
local SEQUENCE: { string } = {
	"DRIVER",
	"WOOD_3",
	"WOOD_5",
	"HYBRID_3",
	"IRON_4",
	"IRON_5",
	"IRON_6",
	"IRON_7",
	"IRON_8",
	"IRON_9",
	"PITCHING_WEDGE",
	"GAP_WEDGE",
	"SAND_WEDGE",
	"LOB_WEDGE",
	"PUTTER",
}

local _index:       number                  = 1
local _locked:      boolean                 = false
local _connections: { RBXScriptConnection } = {}
local _callbacks:   { () -> () }            = {}

local function _notify()
	for _, cb in ipairs(_callbacks) do task.spawn(cb) end
end

--- Current selected club id (e.g. "DRIVER", "IRON_7").
function ClubManager:GetCurrentClubId(): string
	return SEQUENCE[_index]
end

--- Whether cycling is currently locked (during swing / ball flight / putting).
function ClubManager:IsLocked(): boolean
	return _locked
end

--- Current ClubDefinition, or nil if data is missing.
function ClubManager:GetCurrentClub(): ClubData.ClubDefinition?
	return ClubData.GetClub(SEQUENCE[_index])
end

--- Prevent cycling (set during swing and ball flight; clear on landing).
function ClubManager:SetLocked(locked: boolean)
	_locked = locked
	print("[ClubManager] locked=" .. tostring(locked))
end

--- Jump directly to a specific club by id. Silent no-op if id is unknown.
function ClubManager:SetClub(clubId: string)
	for i, id in ipairs(SEQUENCE) do
		if id == clubId then
			if i ~= _index then
				_index = i
				_notify()
			end
			return
		end
	end
end

--- Step toward Driver (less loft / more distance). Wraps from Driver to Putter.
function ClubManager:CyclePrev()
	if _locked then return end
	_index = ((_index - 2) % #SEQUENCE) + 1
	local def = ClubData.GetClub(SEQUENCE[_index])
	print("[ClubPipeline] input selected=" .. SEQUENCE[_index]
		.. "  (" .. (if def then def.displayName else "?") .. ")")
	_notify()
end

--- Step toward Putter (more loft / less distance). Wraps from Putter to Driver.
function ClubManager:CycleNext()
	if _locked then return end
	_index = (_index % #SEQUENCE) + 1
	local def = ClubData.GetClub(SEQUENCE[_index])
	print("[ClubPipeline] input selected=" .. SEQUENCE[_index]
		.. "  (" .. (if def then def.displayName else "?") .. ")")
	_notify()
end

--- Register a callback fired (via task.spawn) when the selected club changes.
function ClubManager:OnChanged(callback: () -> ())
	table.insert(_callbacks, callback)
end

--- Wire up Z / X input. Call once from PlayableHoleControllerModule:Init().
function ClubManager:Init()
	if _initialized then
		warn("[ClubManager] Init called twice — skipping (double-registration would skip clubs by 2)")
		return
	end
	_initialized = true
	print("[ClubManager] Init")
	local keyConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Z then
			print("[ClubManager] Z previous — locked=" .. tostring(_locked))
			ClubManager:CyclePrev()
		elseif input.KeyCode == Enum.KeyCode.X then
			print("[ClubManager] X next — locked=" .. tostring(_locked))
			ClubManager:CycleNext()
		end
	end)
	table.insert(_connections, keyConn)
end

--- Disconnect all input and reset to Driver.
function ClubManager:Destroy()
	for _, conn in ipairs(_connections) do conn:Disconnect() end
	table.clear(_connections)
	table.clear(_callbacks)
	_index       = 1
	_locked      = false
	_initialized = false
end

return ClubManager
