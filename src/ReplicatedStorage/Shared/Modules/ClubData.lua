-- ClubData — Club definitions used by physics, UI, and future progression
-- Shared by server (velocity, spin computation) and client (display, swing feel).
--
-- Each entry has two layers:
--   Physics layer  — loftDegrees, maxSpeed, spinRPM, maxRangeYards, hasDivot
--   Profile layer  — normalized gameplay tuning fields (see ClubProfile below)
--
-- Category values: "Driver" | "Wood" | "Hybrid" | "Iron" | "Wedge" | "Putter"
-- Iron archetype:  "CavityBack" | "Blade" | "MuscleBack" | "HollowBody"
--
-- Profile fields (all 0–1 unless noted):
--   power         — distance potential relative to club class
--   accuracy      — shot dispersion tightness (high = consistent)
--   forgiveness   — mishit penalty reduction (high = forgiving)
--   swingSpeed    — tempo/timing requirement (1 = fastest / hardest to time)
--   spin          — spin generation potential
--   launch        — natural launch angle
--   workability   — ability to shape shots (draw/fade control)
--   difficulty    — 0 = beginner-friendly, 1 = tour-quality challenge
--   mishitPenalty — 0 = very forgiving, 1 = blade-like punishment
--   dispersion    — natural shot scatter (0 = tight, 1 = wide)
--   roll          — rollout after landing (0 = stops fast, 1 = rolls far)
--   shotShapeBias — inherent draw/fade bias (-1 = draw, 0 = straight, +1 = fade)

--!strict

local ClubData = {}

type ClubCategory   = "Driver" | "Wood" | "Hybrid" | "Iron" | "Wedge" | "Putter"
type IronArchetype  = "CavityBack" | "Blade" | "MuscleBack" | "HollowBody"

export type ClubProfile = {
	power:         number,
	accuracy:      number,
	forgiveness:   number,
	swingSpeed:    number,
	spin:          number,
	launch:        number,
	workability:   number,
	difficulty:    number,
	mishitPenalty: number,
	dispersion:    number,
	roll:          number,
	shotShapeBias: number,
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

-- ── Active iron archetype ─────────────────────────────────────────────────────
-- Change this one value to swap the feel of all irons globally.
-- CavityBack = default (most forgiving, balanced).
ClubData.ActiveArchetype = "CavityBack"

-- Multipliers applied to selected iron profile fields when that archetype is active.
-- CavityBack = 1.0 everywhere (baseline).  Others shift forgiveness, spin, accuracy.
ClubData.ArchetypeModifiers = {
	CavityBack = {
		forgiveness   = 1.00,
		spin          = 1.00,
		accuracy      = 1.00,
		dispersion    = 1.00,
		mishitPenalty = 1.00,
	},
	Blade = {
		forgiveness   = 0.55,   -- punishing on mishits, but not brutally so
		spin          = 1.18,   -- slightly elevated spin on pure contact
		accuracy      = 1.08,   -- tighter when struck well
		dispersion    = 0.86,   -- slightly tighter scatter when struck pure
		mishitPenalty = 1.75,   -- significant but not catastrophic punishment
	},
	MuscleBack = {
		forgiveness   = 0.72,
		spin          = 1.10,
		accuracy      = 1.05,
		dispersion    = 0.90,
		mishitPenalty = 1.45,
	},
	HollowBody = {
		forgiveness   = 1.15,   -- most forgiving iron archetype
		spin          = 0.90,   -- fast face = less spin
		accuracy      = 0.95,
		dispersion    = 1.05,   -- slightly wider (speed face)
		mishitPenalty = 0.62,
	},
}

ClubData.Clubs = {

	-- ── Driver ───────────────────────────────────────────────────────────────
	DRIVER = {
		id            = "DRIVER",
		displayName   = "Driver",
		category      = "Driver",
		loftDegrees   = 10,
		maxSpeed      = 420,   -- calibrated: Good full-power → ~255 yd carry
		spinRPM       = 2500,
		maxRangeYards = 280,
		hasDivot      = false,
		profile = {
			power         = 1.00,
			accuracy      = 0.65,
			forgiveness   = 0.55,
			swingSpeed    = 0.85,
			spin          = 0.35,
			launch        = 0.75,
			workability   = 0.55,
			difficulty    = 0.48,
			mishitPenalty = 0.60,
			dispersion    = 0.45,   -- wide — driver misses fairway easily
			roll          = 0.75,   -- lots of rollout
			shotShapeBias = -0.08,  -- slight draw tendency
		},
	},

	-- ── Fairway Woods ────────────────────────────────────────────────────────
	WOOD_3 = {
		id            = "WOOD_3",
		displayName   = "3-Wood",
		category      = "Wood",
		loftDegrees   = 15,
		maxSpeed      = 330,   -- Good full-power → ~230 yd carry
		spinRPM       = 3200,
		maxRangeYards = 245,
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
			dispersion    = 0.38,
			roll          = 0.62,
			shotShapeBias = -0.05,
		},
	},

	WOOD_5 = {
		id            = "WOOD_5",
		displayName   = "5-Wood",
		category      = "Wood",
		loftDegrees   = 19,
		maxSpeed      = 284,   -- Good full-power → ~210 yd carry
		spinRPM       = 3900,
		maxRangeYards = 222,
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
			dispersion    = 0.34,
			roll          = 0.52,
			shotShapeBias = -0.04,
		},
	},

	-- ── Hybrids ──────────────────────────────────────────────────────────────
	HYBRID_3 = {
		id            = "HYBRID_3",
		displayName   = "3-Hybrid",
		category      = "Hybrid",
		loftDegrees   = 20,
		maxSpeed      = 271,   -- Good full-power → ~200 yd carry
		spinRPM       = 3800,
		maxRangeYards = 208,
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
			dispersion    = 0.28,
			roll          = 0.44,
			shotShapeBias = -0.02,
		},
	},

	HYBRID_4 = {
		id            = "HYBRID_4",
		displayName   = "4-Hybrid",
		category      = "Hybrid",
		loftDegrees   = 23,
		maxSpeed      = 250,   -- Good full-power → ~190 yd carry
		spinRPM       = 4500,
		maxRangeYards = 198,
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
			dispersion    = 0.30,
			roll          = 0.42,
			shotShapeBias = -0.02,
		},
	},

	-- ── Irons ────────────────────────────────────────────────────────────────
	IRON_3 = {  -- not in the standard 15-club sequence; kept for archetype reference
		id            = "IRON_3",
		displayName   = "3-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 21,
		maxSpeed      = 252,   -- Good full-power → ~192 yd carry
		spinRPM       = 4200,
		maxRangeYards = 200,
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
			dispersion    = 0.32,
			roll          = 0.38,
			shotShapeBias = 0.00,
		},
	},

	IRON_4 = {
		id            = "IRON_4",
		displayName   = "4-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 24,
		maxSpeed      = 239,   -- Good full-power → ~180 yd carry
		spinRPM       = 4600,
		maxRangeYards = 188,
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
			dispersion    = 0.30,
			roll          = 0.35,
			shotShapeBias = 0.00,
		},
	},

	IRON_5 = {
		id            = "IRON_5",
		displayName   = "5-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 27,
		maxSpeed      = 223,   -- Good full-power → ~170 yd carry
		spinRPM       = 5200,
		maxRangeYards = 176,
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
			dispersion    = 0.28,
			roll          = 0.32,
			shotShapeBias = 0.00,
		},
	},

	IRON_6 = {
		id            = "IRON_6",
		displayName   = "6-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 30,
		maxSpeed      = 208,   -- Good full-power → ~158 yd carry
		spinRPM       = 5800,
		maxRangeYards = 165,
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
			dispersion    = 0.25,
			roll          = 0.28,
			shotShapeBias = 0.00,
		},
	},

	IRON_7 = {
		id            = "IRON_7",
		displayName   = "7-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 34,
		maxSpeed      = 192,   -- Good full-power → ~145 yd carry
		spinRPM       = 6800,
		maxRangeYards = 152,
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
			dispersion    = 0.22,
			roll          = 0.25,
			shotShapeBias = 0.00,
		},
	},

	IRON_7_BLADE = {
		id            = "IRON_7_BLADE",
		displayName   = "7-Iron (Blade)",
		category      = "Iron",
		ironArchetype = "Blade",
		loftDegrees   = 34,
		maxSpeed      = 192,   -- same carry target as standard 7-iron when struck pure
		spinRPM       = 7200,
		maxRangeYards = 152,
		hasDivot      = true,
		profile = {
			power         = 0.60,
			accuracy      = 0.88,
			forgiveness   = 0.35,
			swingSpeed    = 0.65,
			spin          = 0.88,
			launch        = 0.52,
			workability   = 0.95,
			difficulty    = 0.85,
			mishitPenalty = 0.90,
			dispersion    = 0.18,   -- tight when pure
			roll          = 0.24,
			shotShapeBias = 0.00,
		},
	},

	IRON_7_MUSCLE = {
		id            = "IRON_7_MUSCLE",
		displayName   = "7-Iron (Muscle Back)",
		category      = "Iron",
		ironArchetype = "MuscleBack",
		loftDegrees   = 33,
		maxSpeed      = 196,   -- slightly more than IRON_7 (~148 yd carry)
		spinRPM       = 6900,
		maxRangeYards = 155,
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
			dispersion    = 0.20,
			roll          = 0.25,
			shotShapeBias = 0.00,
		},
	},

	IRON_7_HOLLOW = {
		id            = "IRON_7_HOLLOW",
		displayName   = "7-Iron (Hollow Body)",
		category      = "Iron",
		ironArchetype = "HollowBody",
		loftDegrees   = 35,
		maxSpeed      = 200,   -- hot face: ~153 yd carry at Good full
		spinRPM       = 6500,
		maxRangeYards = 160,
		hasDivot      = true,
		profile = {
			power         = 0.65,
			accuracy      = 0.78,
			forgiveness   = 0.88,
			swingSpeed    = 0.62,
			spin          = 0.62,
			launch        = 0.65,
			workability   = 0.55,
			difficulty    = 0.25,
			mishitPenalty = 0.18,
			dispersion    = 0.26,
			roll          = 0.28,
			shotShapeBias = 0.00,
		},
	},

	IRON_8 = {
		id            = "IRON_8",
		displayName   = "8-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 38,
		maxSpeed      = 179,   -- Good full-power → ~132 yd carry
		spinRPM       = 7400,
		maxRangeYards = 138,
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
			dispersion    = 0.20,
			roll          = 0.22,
			shotShapeBias = 0.00,
		},
	},

	IRON_9 = {
		id            = "IRON_9",
		displayName   = "9-Iron",
		category      = "Iron",
		ironArchetype = "CavityBack",
		loftDegrees   = 42,
		maxSpeed      = 169,   -- Good full-power → ~120 yd carry
		spinRPM       = 8000,
		maxRangeYards = 126,
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
			dispersion    = 0.18,
			roll          = 0.18,
			shotShapeBias = 0.02,  -- short irons trend slightly fade
		},
	},

	-- ── Wedges ───────────────────────────────────────────────────────────────
	PITCHING_WEDGE = {
		id            = "PITCHING_WEDGE",
		displayName   = "Pitching Wedge",
		category      = "Wedge",
		loftDegrees   = 46,
		maxSpeed      = 158,   -- Good full-power → ~105 yd carry
		spinRPM       = 8500,
		maxRangeYards = 110,
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
			dispersion    = 0.20,
			roll          = 0.15,
			shotShapeBias = 0.05,
		},
	},

	GAP_WEDGE = {
		id            = "GAP_WEDGE",
		displayName   = "Gap Wedge",
		category      = "Wedge",
		loftDegrees   = 50,
		maxSpeed      = 147,   -- Good full-power → ~90 yd carry
		spinRPM       = 9000,
		maxRangeYards = 94,
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
			dispersion    = 0.22,
			roll          = 0.12,
			shotShapeBias = 0.05,
		},
	},

	SAND_WEDGE = {
		id            = "SAND_WEDGE",
		displayName   = "Sand Wedge",
		category      = "Wedge",
		loftDegrees   = 56,
		maxSpeed      = 135,   -- Good full-power → ~72 yd carry; steep arc stops fast
		spinRPM       = 9200,
		maxRangeYards = 76,
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
			dispersion    = 0.24,
			roll          = 0.08,
			shotShapeBias = 0.06,
		},
	},

	LOB_WEDGE = {
		id            = "LOB_WEDGE",
		displayName   = "Lob Wedge",
		category      = "Wedge",
		loftDegrees   = 62,
		maxSpeed      = 125,   -- Good full-power → ~55 yd carry; very steep, stops almost cold
		spinRPM       = 10000,
		maxRangeYards = 58,
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
			mishitPenalty = 0.80,
			dispersion    = 0.28,
			roll          = 0.05,   -- stops almost immediately
			shotShapeBias = 0.06,
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
			dispersion    = 0.08,   -- very consistent on greens
			roll          = 0.80,   -- putts roll far on smooth surfaces
			shotShapeBias = 0.00,
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
