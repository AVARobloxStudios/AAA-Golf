-- Enums — All game-wide enum constants
-- Read by both server and client

local Enums = {}

Enums.GameState = {
	LOBBY = "LOBBY",
	LOADING = "LOADING",
	PRE_SHOT = "PRE_SHOT",
	SWING = "SWING",
	BALL_FLIGHT = "BALL_FLIGHT",
	SCORE_REVEAL = "SCORE_REVEAL",
	HOLE_END = "HOLE_END",
	ROUND_END = "ROUND_END",
}

Enums.SurfaceType = {
	FAIRWAY = "FAIRWAY",
	GREEN = "GREEN",
	SAND = "SAND",
	WATER = "WATER",
	OOB = "OOB",
	ROUGH = "ROUGH",
}

Enums.ScoreTier = {
	CONDOR = "CONDOR",
	ALBATROSS = "ALBATROSS",
	EAGLE = "EAGLE",
	BIRDIE = "BIRDIE",
	PAR = "PAR",
	BOGEY = "BOGEY",
	DOUBLE_BOGEY = "DOUBLE_BOGEY",
	WORSE = "WORSE",
}

Enums.ClubType = {
	DRIVER = "DRIVER",
	IRON_3 = "IRON_3",
	IRON_7 = "IRON_7",
	PITCHING_WEDGE = "PITCHING_WEDGE",
	PUTTER = "PUTTER",
}

Enums.BallState = {
	IDLE = "IDLE",
	LAUNCHING = "LAUNCHING",
	IN_FLIGHT = "IN_FLIGHT",
	BOUNCING = "BOUNCING",
	SETTLED = "SETTLED",
	PENALTY = "PENALTY",
	HOLED = "HOLED",
}

Enums.CameraMode = {
	LOBBY = "LOBBY",
	DOLLY = "DOLLY",
	FOLLOW_BALL = "FOLLOW_BALL",
	APEX_HOLD = "APEX_HOLD",
	LANDING = "LANDING",
	ORBIT_SCORE = "ORBIT_SCORE",
	PUTT_CAM = "PUTT_CAM",
	HIO_CUT = "HIO_CUT",
}

Enums.SwingState = {
	IDLE = "IDLE",
	AIM = "AIM",
	CHARGING = "CHARGING",
	ACCURACY = "ACCURACY",
	FIRED = "FIRED",
}

Enums.LODTier = {
	FULL = "FULL",
	REDUCED = "REDUCED",
	BILLBOARD = "BILLBOARD",
}

Enums.WeatherState = {
	CLEAR = "Clear",
	CLOUDY = "Cloudy",
	WINDY = "Windy",
	GOLDEN_HOUR = "GoldenHour",
}

return Enums
