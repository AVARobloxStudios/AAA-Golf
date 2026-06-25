-- ValidationSchemas — Input validation shared by client (pre-send) and server (enforcement)
-- Returns (bool, string?) for ok/error pattern

local Enums = require(script.Parent.Enums)

local ValidationSchemas = {}

function ValidationSchemas.ValidateSwingIntent(intent: table): (boolean, string?)
	if type(intent) ~= "table" then
		return false, "intent must be a table"
	end
	if type(intent.power) ~= "number" or intent.power < 0 or intent.power > 1 then
		return false, "power must be 0.0–1.0"
	end
	if type(intent.accuracy) ~= "number" or intent.accuracy < -1 or intent.accuracy > 1 then
		return false, "accuracy must be -1.0–1.0"
	end
	if typeof(intent.aimVector) ~= "Vector3" then
		return false, "aimVector must be a Vector3"
	end
	if intent.aimVector.Magnitude < 0.9 or intent.aimVector.Magnitude > 1.1 then
		return false, "aimVector must be a unit vector"
	end
	if not Enums.ClubType[intent.clubId] then
		return false, "clubId is not a valid ClubType enum"
	end
	if type(intent.timestamp) ~= "number" then
		return false, "timestamp must be a number"
	end
	return true, nil
end

function ValidationSchemas.ValidateGetCourseData(payload: table): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end
	if type(payload.courseId) ~= "string" or #payload.courseId == 0 then
		return false, "courseId must be a non-empty string"
	end
	return true, nil
end

function ValidationSchemas.ValidateGameBusEnvelope(envelope: table): (boolean, string?)
	if type(envelope) ~= "table" then
		return false, "envelope must be a table"
	end
	if type(envelope.eventType) ~= "string" or #envelope.eventType == 0 then
		return false, "eventType must be a non-empty string"
	end
	if type(envelope.timestamp) ~= "number" then
		return false, "timestamp must be a number"
	end
	return true, nil
end

return ValidationSchemas
