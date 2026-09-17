import Foundation

// MARK: - Shared customization contract

struct CurrentCourseSelectionDTO: Codable, Equatable, Hashable {
    let courseSlug: String
    var name: String
}

struct CurriculumCourseDTO: Decodable, Identifiable, Equatable, Hashable {
    let slug: String
    let subjectSlug: String
    let subjectName: String
    let subjectDescription: String
    let icon: String
    let accent: String
    let name: String
    let description: String
    let skills: [String]
    let requirement: String
    let level: Int

    var id: String { slug }
}

struct GradeSpecDTO: Decodable, Identifiable, Equatable, Hashable {
    let stage: String
    let slug: String
    let label: String
    let ageRange: String
    let level: Int

    var id: String { "\(stage):\(slug)" }
}

struct GradeCurriculumDTO: Decodable, Equatable {
    let stage: String
    let grade: String
    let gradeLabel: String
    let ageRange: String
    let frameworkNote: String
    let courses: [CurriculumCourseDTO]
}

// MARK: - Passport curriculum

struct PassportCurriculumContextDTO: Decodable, Equatable {
    let stage: String
    let grade: String
    let gradeLabel: String
    let ageRange: String
    let framework: String?
    let frameworkNote: String
    let selectionSource: String
    let focusSubjects: [String]
    let focusGoals: [String: String]
}

struct PassportCourseConceptDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let slug: String
    let name: String
    let mastery: String
    let confidence: Double

    var conceptID: UUID? { UUID(uuidString: id) }
}

enum PassportCourseSection: String, CaseIterable {
    case focus
    case current
    case required
    case recommended

    var title: String {
        switch self {
        case .focus: "Focus now"
        case .current: "Currently taking"
        case .required: "Grade requirements"
        case .recommended: "Recommended"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: "Extra attention, tied to the goal you chose"
        case .current: "The exact classes in your learning profile"
        case .required: "The rest of Novi’s core map for this grade"
        case .recommended: "Useful breadth beyond the core"
        }
    }
}

struct PassportAreaDTO: Decodable, Identifiable, Equatable, Hashable {
    let slug: String
    let name: String

    var id: String { slug }
}

struct PassportCourseDTO: Decodable, Identifiable, Equatable, Hashable {
    let slug: String
    let subjectSlug: String
    let subjectName: String
    let icon: String
    let accent: String
    let name: String
    let canonicalName: String
    let description: String
    let skills: [String]
    let requirement: String
    let lane: String
    let isCurrent: Bool
    let isFocus: Bool
    let focusGoal: String?
    let focusAreas: [PassportAreaDTO]
    let recommendationReason: String
    let status: String
    let progress: Double
    let learnedConcepts: Int
    let coveredConcepts: Int
    let totalConcepts: Int
    let concepts: [PassportCourseConceptDTO]

    var id: String { slug }

    var section: PassportCourseSection {
        PassportCourseSection(rawValue: lane) ?? .recommended
    }

    var statusLabel: String {
        switch status {
        case "mastered": "Mastered"
        case "learned": "Learned"
        case "in_progress": "In progress"
        default: "Not started"
        }
    }

    var statusIcon: String {
        switch status {
        case "mastered": "seal.fill"
        case "learned": "checkmark.seal.fill"
        case "in_progress": "circle.lefthalf.filled"
        default: "circle"
        }
    }
}

// MARK: - New write contract

struct LearningOnboardingBody: Encodable {
    let stage: String
    let grade: String
    let curriculum: String?
    let currentCourses: [CurrentCourseSelectionDTO]
    let focusSubjectSlugs: [String]
    let focusGoals: [String: String]
    let focusAreas: [String: [String]]
    let learningPreferences: [String]
    let goals: [String]
    let language: String
}

struct LearningProfilePatchBody: Encodable {
    let stage: String
    let grade: String
    let curriculum: String?
    let currentCourses: [CurrentCourseSelectionDTO]
    let focusSubjectSlugs: [String]
    let focusGoals: [String: String]
    let focusAreas: [String: [String]]
}
