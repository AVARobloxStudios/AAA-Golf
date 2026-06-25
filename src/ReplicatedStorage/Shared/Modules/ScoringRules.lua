-- ScoringRules — Par thresholds, penalty values, XP/Coin formulas
-- Pure data: no state, no side effects

local ScoringRules = {}

-- Score tier classification by strokes-relative-to-par
ScoringRules.TIERS = {
	[-4] = "CONDOR",
	[-3] = "ALBATROSS",
	[-2] = "EAGLE",
	[-1] = "BIRDIE",
	[0]  = "PAR",
	[1]  = "BOGEY",
	[2]  = "DOUBLE_BOGEY",
	[99] = "WORSE",     -- catch-all for anything > double bogey
}

-- XP awarded per score tier
ScoringRules.TIER_XP = {
	CONDOR       = 200,
	ALBATROSS    = 180,
	EAGLE        = 150,
	BIRDIE       = 100,
	PAR          = 75,
	BOGEY        = 60,
	DOUBLE_BOGEY = 50,
	WORSE        = 50,
}

-- Coins awarded per score tier
ScoringRules.TIER_COINS = {
	CONDOR       = 500,
	ALBATROSS    = 400,
	EAGLE        = 300,
	BIRDIE       = 150,
	PAR          = 100,
	BOGEY        = 60,
	DOUBLE_BOGEY = 40,
	WORSE        = 25,
}

-- Hazard penalty strokes
ScoringRules.PENALTY_STROKES = {
	WATER = 1,
	OOB   = 1,
	SAND  = 0,  -- sand is a lie penalty (position only), not a stroke
}

-- Maximum strokes per hole before forced hole-out
ScoringRules.MAX_STROKES_PER_HOLE = 10

function ScoringRules.ClassifyScore(strokes: number, par: number): string
	local delta = strokes - par
	if delta <= -4 then
		return "CONDOR"
	end
	local tier = ScoringRules.TIERS[delta]
	return tier or "WORSE"
end

return ScoringRules
