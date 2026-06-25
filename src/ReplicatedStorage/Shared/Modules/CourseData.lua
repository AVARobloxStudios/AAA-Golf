-- CourseData — Static course metadata: hole geometry, par, hazard zones
-- Populated at runtime from Workspace Metadata Values by CourseService
-- Stubs here; real data loaded from Workspace in Sprint 3+

local CourseData = {}

CourseData.Courses = {
	course_1 = {
		id = "course_1",
		displayName = "Sunnybrook Meadows",
		totalHoles = 9,
		holes = {
			-- Populated at runtime from Workspace/Courses/Course_1_SunnybrookMeadows/Holes/Hole_XX/Metadata
		},
	},
}

function CourseData.GetCourse(courseId: string)
	return CourseData.Courses[courseId]
end

return CourseData
