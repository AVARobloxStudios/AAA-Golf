-- CourseManifest — Registry of all available courses and their unlock state
-- Stub for Sprint 0; populated fully in Sprint 4 (CourseService)

local CourseManifest = {}

CourseManifest.Courses = {
	{
		id = "course_1",
		displayName = "Sunnybrook Meadows",
		holeCount = 9,
		unlockedByDefault = true,
		workspacePath = "Courses/Course_1_SunnybrookMeadows",
	},
	{
		id = "course_2",
		displayName = "Coral Cove",
		holeCount = 18,
		unlockedByDefault = false,
		workspacePath = "Courses/Course_2_CoralCove",
	},
	{
		id = "course_3",
		displayName = "Sakura Highlands",
		holeCount = 18,
		unlockedByDefault = false,
		workspacePath = "Courses/Course_3_SakuraHighlands",
	},
}

return CourseManifest
