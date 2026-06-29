--!strict
-- PuttingModule — Client, Milestone 1.9
-- Activated when ball lands within PUTTING_RADIUS of cup.
-- Intercepts SwingResult before it goes to the server and flattens the launch
-- to a near-horizontal roll with reduced power.

local PuttingModule = {}

local _active = false

-- 0.48 client scale: server bypasses the PUTTER club-power ratio for isPutt shots,
-- so effective speed = shotPower × 0.48 × LaunchSpeedScale(3.2).
-- At 40% swing (shotPower≈40): 40×0.48×3.2 ≈ 61 studs/s → ~32 stud roll.
local PUTT_POWER_SCALE: number = 0.48
local PUTT_LAUNCH_Y:    number = 0.02   -- essentially flat

function PuttingModule:Activate()
	_active = true
end

function PuttingModule:Deactivate()
	_active = false
end

function PuttingModule:IsActive(): boolean
	return _active
end

-- Returns a modified copy of swingResult with putting physics applied.
-- Pass-through when not active.
function PuttingModule:ModifySwingResult(swingResult: any): any
	if not _active then return swingResult end

	local dir = swingResult.launchDirection :: Vector3
	local flat = Vector3.new(dir.X, PUTT_LAUNCH_Y, dir.Z)
	if flat.Magnitude < 0.001 then flat = Vector3.new(0, PUTT_LAUNCH_Y, -1) end

	return {
		shotPower       = (swingResult.shotPower :: number) * PUTT_POWER_SCALE,
		launchDirection = flat.Unit,
		contactQuality  = swingResult.contactQuality,
		shotShape       = "Straight",
		carryMultiplier = 1.0,
		rollMultiplier  = 1.0,
		sideSpinInput   = 0,
		backSpinInput   = 0,
		isPutt          = true,
	}
end

return PuttingModule
