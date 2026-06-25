-- ClubData — Per-club stats used by physics and UI
-- Read by server (velocity computation) and client (display, shadow physics)

local ClubData = {}

ClubData.Clubs = {
	DRIVER = {
		id = "DRIVER",
		displayName = "Driver",
		loftDegrees = 10,
		maxSpeed = 420,      -- studs/s at 100% power
		spinRPM = 2500,
		maxRangeYards = 280,
		hasDivot = false,
	},
	IRON_3 = {
		id = "IRON_3",
		displayName = "3-Iron",
		loftDegrees = 21,
		maxSpeed = 360,
		spinRPM = 4200,
		maxRangeYards = 210,
		hasDivot = true,
	},
	IRON_7 = {
		id = "IRON_7",
		displayName = "7-Iron",
		loftDegrees = 34,
		maxSpeed = 300,
		spinRPM = 6800,
		maxRangeYards = 160,
		hasDivot = true,
	},
	PITCHING_WEDGE = {
		id = "PITCHING_WEDGE",
		displayName = "Pitching Wedge",
		loftDegrees = 46,
		maxSpeed = 240,
		spinRPM = 8500,
		maxRangeYards = 120,
		hasDivot = true,
	},
	PUTTER = {
		id = "PUTTER",
		displayName = "Putter",
		loftDegrees = 4,
		maxSpeed = 80,
		spinRPM = 200,
		maxRangeYards = nil, -- N/A
		hasDivot = false,
	},
}

function ClubData.GetClub(clubId: string)
	return ClubData.Clubs[clubId]
end

return ClubData
