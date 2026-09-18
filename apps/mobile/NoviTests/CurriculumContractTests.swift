import XCTest
@testable import Novi

final class CurriculumContractTests: XCTestCase {

    func testClientGradesMatchTheSupportedStages() {
        XCTAssertEqual(Onb.grades(for: "middle").map(\.slug), ["6", "7", "8"])
        XCTAssertEqual(Onb.grades(for: "high").map(\.slug), ["9", "10", "11", "12"])
        XCTAssertEqual(
            Onb.grades(for: "college").map(\.slug),
            ["freshman", "sophomore", "junior", "senior", "grad"]
        )
        XCTAssertEqual(Onb.grades(for: "other").map(\.slug), ["adult", "self-taught"])
        XCTAssertEqual(
            Set(Onb.focusGoals.map(\.slug)),
            [
                "build_foundations", "catch_up", "improve_grades",
                "exam_readiness", "get_ahead", "build_confidence",
            ]
        )
        XCTAssertEqual(
            Set(Onb.areas(for: "biology").map(\.slug)),
            ["cells", "genetics", "physiology", "ecology"]
        )
        XCTAssertFalse(Onb.areas(for: "mathematics").isEmpty)
    }

    func testOnboardingBodyEncodesConcreteCourses() throws {
        let body = LearningOnboardingBody(
            stage: "high",
            grade: "11",
            curriculum: "AP",
            currentCourses: [
                CurrentCourseSelectionDTO(courseSlug: "high-11-mathematics", name: "AP Calc BC"),
            ],
            focusSubjectSlugs: ["mathematics"],
            focusGoals: ["mathematics": "exam_readiness"],
            focusAreas: ["mathematics": ["calculus"]],
            learningPreferences: ["short_video"],
            goals: ["exam_prep"],
            language: "en"
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.novi.encode(body)) as? [String: Any]
        )
        XCTAssertEqual(json["stage"] as? String, "high")
        XCTAssertNotNil(json["current_courses"])
        XCTAssertNotNil(json["focus_subject_slugs"])
        XCTAssertNotNil(json["focus_goals"])
        XCTAssertNotNil(json["focus_areas"])
        XCTAssertNil(json["subject_slugs"])
    }

    func testOnboardingBodyOmitsUnpickedSubjectAreas() throws {
        let body = LearningOnboardingBody(
            stage: "high",
            grade: "11",
            curriculum: "AP",
            currentCourses: [
                CurrentCourseSelectionDTO(courseSlug: "high-11-biology", name: ""),
                CurrentCourseSelectionDTO(courseSlug: "high-11-mathematics", name: ""),
                CurrentCourseSelectionDTO(courseSlug: "high-11-history", name: ""),
            ],
            focusSubjectSlugs: ["biology"],
            focusGoals: ["biology": "catch_up"],
            focusAreas: ["biology": ["cells", "ecology"]],
            learningPreferences: [],
            goals: [],
            language: "en"
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.novi.encode(body)) as? [String: Any]
        )
        let areas = try XCTUnwrap(json["focus_areas"] as? [String: [String]])
        XCTAssertEqual(areas["biology"], ["cells", "ecology"])
        XCTAssertNil(areas["mathematics"])
        XCTAssertNil(areas["history"])
    }

    func testPassportCourseMapDecodesFromTheAPIShape() throws {
        let data = """
        {
          "concepts_covered": 2,
          "concepts_learned": 1,
          "subjects": 1,
          "projects": 0,
          "sessions": 3,
          "curriculum": {
            "stage": "high",
            "grade": "11",
            "grade_label": "Grade 11",
            "age_range": "Ages 16–17",
            "framework": "AP",
            "framework_note": "note",
            "selection_source": "saved",
            "focus_subjects": ["mathematics"],
            "focus_goals": {"mathematics": "exam_readiness"}
          },
          "course_map": [{
            "slug": "high-11-mathematics",
            "subject_slug": "mathematics",
            "subject_name": "Mathematics",
            "icon": "function",
            "accent": "#4C6FFF",
            "name": "AP Calculus BC",
            "canonical_name": "Functions, Trigonometry & Statistics",
            "description": "For Grade 11, this course develops functions.",
            "skills": ["functions", "trigonometry", "statistics"],
            "requirement": "required",
            "lane": "focus",
            "is_current": true,
            "is_focus": true,
            "focus_goal": "Prepare for an exam",
            "focus_areas": [{"slug": "calculus", "name": "Calculus"}],
            "recommendation_reason": "Current course; Prepare for an exam in Mathematics.",
            "status": "in_progress",
            "progress": 0.4,
            "learned_concepts": 1,
            "covered_concepts": 2,
            "total_concepts": 5,
            "concepts": [{
              "id": "00000000-0000-0000-0000-000000000001",
              "slug": "derivatives",
              "name": "Derivatives",
              "mastery": "learned",
              "confidence": 0.7
            }]
          }],
          "subject_cards": [],
          "stamps": []
        }
        """.data(using: .utf8)!

        let passport = try JSONDecoder.novi.decode(PassportDTO.self, from: data)
        XCTAssertEqual(passport.curriculum?.gradeLabel, "Grade 11")
        XCTAssertEqual(passport.courseMap.count, 1)
        let course = try XCTUnwrap(passport.courseMap.first)
        XCTAssertEqual(course.section, .focus)
        XCTAssertEqual(course.name, "AP Calculus BC")
        XCTAssertEqual(course.statusLabel, "In progress")
        XCTAssertTrue(course.isCurrent)
        XCTAssertEqual(course.focusAreas.first?.slug, "calculus")
        XCTAssertEqual(course.concepts.first?.name, "Derivatives")
    }

    func testGradeCurriculumDecodesFromTheAPIShape() throws {
        let data = """
        {
          "stage": "high",
          "grade": "11",
          "grade_label": "Grade 11",
          "age_range": "Ages 16–17",
          "framework_note": "note",
          "courses": [{
            "slug": "high-11-mathematics",
            "subject_slug": "mathematics",
            "subject_name": "Mathematics",
            "subject_description": "Algebra.",
            "icon": "function",
            "accent": "#4C6FFF",
            "name": "Functions, Trigonometry & Statistics",
            "description": "For Grade 11.",
            "skills": ["functions", "trigonometry", "statistics"],
            "requirement": "required",
            "level": 3
          }]
        }
        """.data(using: .utf8)!
        let map = try JSONDecoder.novi.decode(GradeCurriculumDTO.self, from: data)
        XCTAssertEqual(map.courses.first?.subjectName, "Mathematics")
        XCTAssertEqual(map.ageRange, "Ages 16–17")
    }
}
