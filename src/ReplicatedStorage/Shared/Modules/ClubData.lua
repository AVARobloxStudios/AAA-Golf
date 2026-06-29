-- ClubData — Club definitions used by physics, UI, and future progression
-- Shared by server (velocity, spin computation) and client (display, swing feel).
--
-- Each entry has two layers:
--   Physics layer  — loftDegrees, maxSpeed, spinRPM, maxRangeYards, hasDivot
--   Profile layer  — normalized 0–1 gameplay tuning fields for future systems
--
-- Category values: "Driver" | "Wood" | "Hybrid" | "Iron" | "Wedge" | "Putter"
-- Iron archetype:  "CavityBack" | "Blade" | "MuscleBack" | "HollowBody"
--
-- Profile fields (all 0–1, higher = more of that attribute):
--   power         — distance potential relative to club class
--   accuracy      — shot dispersion tightness
--   forgiveness   — mishit penalty reduction
--   swingSpeed    — tempo/timing requirement (1 = fastest / hardest to time)
--   spin          — spin generation potential
--   launch        — natural launch angle
--   workability   — ability to intentionally shape shots (draw/fade control)
--   difficulty    — 0 = beginner-friendly, 1 = tour-quality challenge
--   mishitPenalty — 0 = very forgiving on mishits, 1 = blade-like punishment

--!strict

local ClubData = {}

type ClubCategory   = "Driver" | "Wood" | "Hybrid" | "Iron" | "Wedge" | "Putter"
type IronArchetype  = "CavityBack" | "Blade" | "MuscleBack" | "HollowBody"

export type ClubProfile = {
	power:        number,
	accuracy:     number,
	forgiveness:  number,
	swingSpeed:   number,
	spin:         number,
	launch:       number,
	workability:  number,
	difficulty:   number,
	mishitPenalty:number,
}

export type ClubDefinition = {
	id:             string,
	displayName:    string,
	category:       ClubCategory,
	ironArchetype:  IronArchetype?,
	-- Physics
	loftDegrees:    number,
	maxSpeed:       number,     -- studs/s at 100% power
	spinRPM:        number,
	maxRangeYards:  number?,
	hasDivot:       boolean,
	-- Gameplay profile
	profile:        ClubProfile,
}

ClubData.Clubs = {

	-- ── Driver ───────────────────────────────────────────────────────────────
	DRIVER = {
		id            = "DRIVER",
		displayName   = "Driver",
		category      = "Driver",
		loftDegrees   = 10,
		maxSpeed      = 420,
		spinRPM       = 2500,
		maxRangeYards = 280,
		hasDivot      = false,
		profile = {
			power         = 1.00,
			accuracy      = 0.65,
			forgiveness   = 0.55,   -- low forgiveness: driver punishes off-centre contact
			swingSpeed    = 0.85,
			spin          = 0.35,
			launch        = 0.75,
			workability   = 0.55,
			difficulty    = 0.48,
			mishitPenalty = 0.60,
		},
	},

	-- ── Fairway Woods ────────────────────────────────────────────────────────
	WOOD_3 = {
		id            = "WOOD_3",
		displayName   = "3-Wood",
		category      = "Wood",
		loftDegrees   = 15,
		maxSpeed      = 390,
		spinRPM       = 3200,
		maxRangeYards = 250,
		hasDivot      = false,
		profile = {
			power         = 0.90,
			accuracy      = 0.72,
			forgiveness   = 0.75,
			swingSpeed    = 0.80,
			spin          = 0.42,
			launch        = 0.68,
			workability   = 0.60,
			difficulty    = 0.38,
			mishitPenalty = 0.40,
		},
	},

	WOOD_5 = {
		id            = "WOOD_5",
		displayName   = "5-Wood",
		category      = "Wood",
		loftDegrees   = 19,
		maxSpeed      = 360,
		spinRPM       = 3900,
		maxRangeYards = 225,
		hasDivot      = false,
		profile = {
			power         = 0.82,
			accuracy      = 0.76,
			forgiveness   = 0.78,
			swingSpeed    = 0.75,
			spin          = 0.50,
			launch        = 0.62,
			workability   = 0.62,
			difficulty    = 0.33,
			mishitPenalty = 0.35,
		},
	},

	-- ── Hybrids ──────────────────────────────────────────────────────────────
	HYBRID_3 = {
		id            = "HYBRID_3",
		displayName   = "3-Hybrid",
		category      = "Hybrid",
		loftDegrees   = 20,
		maxSpeed      = 355,
		spinRPM       = 3800,
		maxRangeYards = 215,
		hasDivot      = false,
		profile = {
			power         = 0.78,
			accuracy      = 0.79,
			forgiveness   = 0.86,
			swingSpeed    = 0.72,
			spin          = 0.54,
			launch        = 0.62,
			workability   = 0.56,
			difficulty    = 0.26,
			mishitPenalty = 0.26,
		},
	},

	HYBRID_4 = {
		id            = "HYBRID_4",
		displayName   = "4-Hybrid",
		category      = "Hybrid",
		loftDegrees   = 23,
		maxSpeed      = 340,
		spinRPM       = 4500,
		maxRangeYards = 205,
		hasDivot      = false,
		profile = {
			power         = 0.75,
			accuracy      = 0.80,
			forgiveness   = 0.84,
			swingSpeed    = 0.70,
			spin          = 0.56,
			launch        = 0.60,
			workability   = 0.58,
			difficulty    = 0.28,
			mishitPenalty = 0.28,
		},
	},

	-- ── Irons ────────────────────────────────────────────────────────────────
	IRON_3 = {  -- not in the standard 15-club sequence; kept for archetype reference
		id            = "IRON_3",
		displayName   = "3-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 21,
		maxSpeed      = 360,
		spinRPM       = 4200,
		maxRangeYards = 210,
		hasDivot      = true,
		profile = {
			power         = 0.72,
			accuracy      = 0.78,
			forgiveness   = 0.76,
			swingSpeed    = 0.72,
			spin          = 0.60,
			launch        = 0.58,
			workability   = 0.65,
			difficulty    = 0.45,
			mishitPenalty = 0.38,
		},
	},

	IRON_4 = {
		id            = "IRON_4",
		displayName   = "4-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 24,
		maxSpeed      = 345,
		spinRPM       = 4600,
		maxRangeYards = 200,
		hasDivot      = true,
		profile = {
			power         = 0.69,
			accuracy      = 0.79,
			forgiveness   = 0.78,
			swingSpeed    = 0.70,
			spin          = 0.62,
			launch        = 0.57,
			workability   = 0.66,
			difficulty    = 0.42,
			mishitPenalty = 0.36,
		},
	},

	IRON_5 = {
		id            = "IRON_5",
		displayName   = "5-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 27,
		maxSpeed      = 330,
		spinRPM       = 5200,
		maxRangeYards = 185,
		hasDivot      = true,
		profile = {
			power         = 0.65,
			accuracy      = 0.80,
			forgiveness   = 0.80,
			swingSpeed    = 0.68,
			spin          = 0.66,
			launch        = 0.57,
			workability   = 0.67,
			difficulty    = 0.40,
			mishitPenalty = 0.32,
		},
	},

	IRON_6 = {
		id            = "IRON_6",
		displayName   = "6-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 30,
		maxSpeed      = 315,
		spinRPM       = 5800,
		maxRangeYards = 172,
		hasDivot      = true,
		profile = {
			power         = 0.62,
			accuracy      = 0.81,
			forgiveness   = 0.81,
			swingSpeed    = 0.67,
			spin          = 0.69,
			launch        = 0.57,
			workability   = 0.67,
			difficulty    = 0.37,
			mishitPenalty = 0.29,
		},
	},

	IRON_7 = {
		id            = "IRON_7",
		displayName   = "7-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 34,
		maxSpeed      = 300,
		spinRPM       = 6800,
		maxRangeYards = 160,
		hasDivot      = true,
		profile = {
			power         = 0.58,
			accuracy      = 0.82,
			forgiveness   = 0.82,
			swingSpeed    = 0.65,
			spin          = 0.72,
			launch        = 0.56,
			workability   = 0.68,
			difficulty    = 0.35,
			mishitPenalty = 0.25,
		},
	},

	IRON_7_BLADE = {
		id            = "IRON_7_BLADE",
		displayName   = "7-Iron (Blade)",
		category      = "Iron",
		ironArchetype = "Blade",
		loftDegrees   = 34,
		maxSpeed      = 300,
		spinRPM       = 7200,
		maxRangeYards = 160,
		hasDivot      = true,
		profile = {
			power         = 0.60,   -- slightly more when struck pure
			accuracy      = 0.88,
			forgiveness   = 0.35,   -- blade = punishing on mishits
			swingSpeed    = 0.65,
			spin          = 0.88,   -- blades generate more spin when struck correctly
			launch        = 0.52,
			workability   = 0.95,   -- blade's main advantage: extreme shot shaping
			difficulty    = 0.85,
			mishitPenalty = 0.90,
		},
	},

	IRON_7_MUSCLE = {
		id            = "IRON_7_MUSCLE",
		displayName   = "7-Iron (Muscle Back)",
		category      = "Iron",
		ironArchetype = "MuscleBack",
		loftDegrees   = 33,
		maxSpeed      = 305,
		spinRPM       = 6900,
		maxRangeYards = 162,
		hasDivot      = true,
		profile = {
			power         = 0.62,
			accuracy      = 0.86,
			forgiveness   = 0.52,
			swingSpeed    = 0.65,
			spin          = 0.82,
			launch        = 0.54,
			workability   = 0.85,
			difficulty    = 0.70,
			mishitPenalty = 0.72,
		},
	},

	IRON_7_HOLLOW = {
		id            = "IRON_7_HOLLOW",
		displayName   = "7-Iron (Hollow Body)",
		category      = "Iron",
		ironArchetype = "HollowBody",
		loftDegrees   = 35,
		maxSpeed      = 315,
		spinRPM       = 6500,
		maxRangeYards = 165,
		hasDivot      = true,
		profile = {
			power         = 0.65,   -- hollow body = fastest face, most distance of iron archetypes
			accuracy      = 0.78,
			forgiveness   = 0.88,   -- most forgiving iron archetype
			swingSpeed    = 0.62,
			spin          = 0.62,
			launch        = 0.65,
			workability   = 0.55,
			difficulty    = 0.25,
			mishitPenalty = 0.18,
		},
	},

	IRON_8 = {
		id            = "IRON_8",
		displayName   = "8-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 38,
		maxSpeed      = 285,
		spinRPM       = 7400,
		maxRangeYards = 148,
		hasDivot      = true,
		profile = {
			power         = 0.55,
			accuracy      = 0.83,
			forgiveness   = 0.83,
			swingSpeed    = 0.63,
			spin          = 0.76,
			launch        = 0.56,
			workability   = 0.68,
			difficulty    = 0.32,
			mishitPenalty = 0.22,
		},
	},

	IRON_9 = {
		id            = "IRON_9",
		displayName   = "9-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 42,
		maxSpeed      = 265,
		spinRPM       = 8000,
		maxRangeYards = 135,
		hasDivot      = true,
		profile = {
			power         = 0.50,
			accuracy      = 0.84,
			forgiveness   = 0.84,
			swingSpeed    = 0.60,
			spin          = 0.80,
			launch        = 0.54,
			workability   = 0.70,
			difficulty    = 0.30,
			mishitPenalty = 0.20,
		},
	},

	-- ── Wedges ───────────────────────────────────────────────────────────────
	PITCHING_WEDGE = {
		id            = "PITCHING_WEDGE",
		displayName   = "Pitching Wedge",
		category      = "Wedge",
		loftDegrees   = 46,
		maxSpeed      = 240,
		spinRPM       = 8500,
		maxRangeYards = 120,
		hasDivot      = true,
		profile = {
			power         = 0.45,
			accuracy      = 0.85,
			forgiveness   = 0.78,
			swingSpeed    = 0.55,
			spin          = 0.85,
			launch        = 0.50,
			workability   = 0.70,
			difficulty    = 0.30,
			mishitPenalty = 0.32,
		},
	},

	GAP_WEDGE = {
		id            = "GAP_WEDGE",
		displayName   = "Gap Wedge",
		category      = "Wedge",
		loftDegrees   = 50,
		maxSpeed      = 215,
		spinRPM       = 9000,
		maxRangeYards = 105,
		hasDivot      = true,
		profile = {
			power         = 0.40,
			accuracy      = 0.84,
			forgiveness   = 0.75,
			swingSpeed    = 0.52,
			spin          = 0.88,
			launch        = 0.52,
			workability   = 0.74,
			difficulty    = 0.32,
			mishitPenalty = 0.36,
		},
	},

	SAND_WEDGE = {
		id            = "SAND_WEDGE",
		displayName   = "Sand Wedge",
		category      = "Wedge",
		loftDegrees   = 56,
		maxSpeed      = 190,
		spinRPM       = 9200,
		maxRangeYards = 90,
		hasDivot      = true,
		profile = {
			power         = 0.35,
			accuracy      = 0.82,
			forgiveness   = 0.72,
			swingSpeed    = 0.48,
			spin          = 0.92,
			launch        = 0.55,
			workability   = 0.78,
			difficulty    = 0.38,
			mishitPenalty = 0.40,
		},
	},

	LOB_WEDGE = {
		id            = "LOB_WEDGE",
		displayName   = "Lob Wedge",
		category      = "Wedge",
		loftDegrees   = 62,
		maxSpeed      = 155,
		spinRPM       = 10000,
		maxRangeYards = 70,
		hasDivot      = true,
		profile = {
			power         = 0.28,
			accuracy      = 0.75,
			forgiveness   = 0.58,
			swingSpeed    = 0.42,
			spin          = 0.98,
			launch        = 0.72,
			workability   = 0.90,
			difficulty    = 0.65,
			mishitPenalty = 0.80,   -- lob wedge is the most punishing club on mishits
		},
	},

	-- ── Putter ───────────────────────────────────────────────────────────────
	PUTTER = {
		id            = "PUTTER",
		displayName   = "Putter",
		category      = "Putter",
		loftDegrees   = 4,
		maxSpeed      = 80,
		spinRPM       = 200,
		maxRangeYards = nil,
		hasDivot      = false,
		profile = {
			power         = 0.15,
			accuracy      = 0.95,
			forgiveness   = 0.88,
			swingSpeed    = 0.20,
			spin          = 0.05,
			launch        = 0.05,
			workability   = 0.10,
			difficulty    = 0.20,
			mishitPenalty = 0.15,
		},
	},
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Returns the definition for the currently active club.
-- Gameplay always uses the Driver until club selection is implemented.
function ClubData.GetActiveClub(): ClubDefinition
	return ClubData.Clubs["DRIVER"]
end

-- Looks up a club by id (case-sensitive). Returns nil if not found.
function ClubData.GetClub(clubId: string): ClubDefinition?
	return ClubData.Clubs[clubId]
end

-- Returns all clubs belonging to the given category.
function ClubData.GetClubsByCategory(category: ClubCategory): {ClubDefinition}
	local result: {ClubDefinition} = {}
	for _, def in pairs(ClubData.Clubs) do
		if def.category == category then
			table.insert(result, def)
		end
	end
	return result
end

-- Returns all clubs with a specific iron archetype.
-- Returns an empty table for non-Iron categories.
function ClubData.GetIronsByArchetype(archetype: IronArchetype): {ClubDefinition}
	local result: {ClubDefinition} = {}
	for _, def in pairs(ClubData.Clubs) do
		if def.category == "Iron" and def.ironArchetype == archetype then
			table.insert(result, def)
		end
	end
	return result
end

return ClubData
