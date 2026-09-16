import Foundation

/// Wire types, one per API payload. Names are camelCase and the decoder
/// converts from the API's snake_case, so there are no `CodingKeys` to drift.

// MARK: - Auth & profile

struct TokenPairDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct UserDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let email: String
    let username: String
    let displayName: String
    let avatarSeed: String
    let isAdmin: Bool
    let isOnboarded: Bool
    let createdAt: Date
}

struct ProfileDTO: Decodable, Equatable {
    let stage: String?
    let grade: String?
    let curriculum: String?
    let subjectOrder: [String]
    let subjectInterests: [String: Double]
    let learningPreferences: [String]
    let goals: [String]
    let language: String
    let bio: String
}

struct AuthResponseDTO: Decodable {
    let user: UserDTO
    let tokens: TokenPairDTO
}

struct MeDTO: Decodable, Equatable {
    let user: UserDTO
    let profile: ProfileDTO?
}

struct SubjectDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let slug: String
    let name: String
    let description: String
    let icon: String
    let accent: String
}

struct ConceptDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let slug: String
    let name: String
    let subjectId: UUID
    let description: String
    let difficulty: Int
}

// MARK: - Content

struct ConceptRefDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let slug: String
    let name: String
}

struct ContentDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let platform: String
    let title: String
    let description: String
    let creator: String
    let url: String?
    let mediaUrl: String?
    let thumbnailUrl: String?
    /// The masonry needs a card's height before laying it out, so the cover's
    /// aspect ratio ships with the item rather than being measured after load.
    let thumbnailRatio: Double
    let mediaKind: String
    let language: String
    let durationSeconds: Int?
    let topic: String
    let tags: [String]
    let likes: Int
    let comments: Int
    let difficulty: Int
    /// True while the store holds generated stand-ins. The card shows a marker:
    /// placeholder content that looks ingested makes the app look finished when
    /// the hardest part has not been built.
    let isSample: Bool
    let subjectId: UUID?
    let publishedAt: Date?
    let concepts: [ConceptRefDTO]

    /// Seed for the drawn cover. Stable across launches and devices.
    var coverSeed: String { "cover-" + id.uuidString }
}

struct FeedItemDTO: Decodable, Identifiable, Equatable, Hashable {
    let content: ContentDTO
    let score: Double
    let reason: String
    let isSaved: Bool
    let isLiked: Bool

    var id: UUID { content.id }
}

struct FeedResponseDTO: Decodable {
    let items: [FeedItemDTO]
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct ContentDetailDTO: Decodable {
    let content: ContentDTO
    let concepts: [ConceptDTO]
    let related: [ContentDTO]
    let isSaved: Bool
    let isLiked: Bool
    let reason: String
}

struct DiscussionCommentDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let author: String
    let body: String
    let upvotes: Int
}

struct TranslationDTO: Decodable, Equatable, Hashable {
    let language: String?
    let title: String?
    let body: String?
    let comments: [String]?
}

struct SummaryDTO: Decodable, Equatable, Hashable {
    let mainIdeas: [String]?
    let agreement: [String]?
    let disagreement: [String]?
    let commonMistakes: [String]?
    let usefulResources: [String]?
}

struct DiscussionDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let platform: String
    let community: String
    let title: String
    let body: String
    let author: String
    let url: String?
    let language: String
    let upvotes: Int
    let commentCount: Int
    let isSample: Bool
    let comments: [DiscussionCommentDTO]
    let translation: TranslationDTO?
    let summary: SummaryDTO?
}

// MARK: - Ask

struct ExplanationDTO: Decodable, Equatable {
    let concept: String
    let summary: String
    let simpleExplanation: String
    let whyItWorks: String
    let example: String
    let commonMisconception: String
    let relatedConcepts: [String]
    let searchQueries: [String]
}

struct RelatedConceptDTO: Decodable, Identifiable, Equatable, Hashable {
    let name: String
    let id: String?
    let slug: String?

    /// A concept the model named that our graph does not have is still part of
    /// the answer; it renders as a plain, non-tappable chip rather than being
    /// dropped from the list the learner was shown.
    var conceptID: UUID? { id.flatMap(UUID.init(uuidString:)) }
}

struct AskResponseDTO: Decodable, Equatable {
    /// Identity is the question id alone: two responses to the same question
    /// are the same answer, and deep-comparing the whole discovery rail on
    /// every body evaluation would be wasted work.
    static func == (a: AskResponseDTO, b: AskResponseDTO) -> Bool {
        a.questionId == b.questionId
    }

    let questionId: UUID
    let explanation: ExplanationDTO
    let watch: [ContentDTO]
    let read: [ContentDTO]
    let discuss: [DiscussionDTO]
    let relatedConcepts: [RelatedConceptDTO]
}

struct SearchResponseDTO: Decodable {
    struct SearchConcept: Decodable {
        let id: UUID
        let slug: String
        let name: String
        let description: String
        let difficulty: Int
        let subjectName: String?
    }
    let query: String
    let concept: SearchConcept?
    let content: [ContentDTO]
    let discussions: [DiscussionDTO]
}

// MARK: - Quiz

struct QuizQuestionDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ordinal: Int
    let prompt: String
    let options: [String]
}

struct QuizDTO: Decodable {
    let id: UUID
    let conceptId: UUID
    let conceptName: String
    let difficulty: Int
    let questions: [QuizQuestionDTO]
}

struct GradedAnswerDTO: Decodable, Identifiable, Equatable {
    let questionId: UUID
    let selectedIndex: Int
    let correctIndex: Int
    let isCorrect: Bool
    let explanation: String

    var id: UUID { questionId }
}

struct StampDTO: Decodable, Identifiable, Equatable, Hashable {
    let kind: String
    let key: String
    let title: String
    let subtitle: String
    let icon: String

    var id: String { "\(kind):\(key)" }
}

struct QuizResultDTO: Decodable {
    let quizId: UUID
    let score: Double
    let correct: Int
    let total: Int
    let answers: [GradedAnswerDTO]
    let conceptMastery: String
    let newStamps: [StampDTO]
}

// MARK: - Passport

struct PassportConceptDTO: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let slug: String
    let name: String
    let mastery: String
    let confidence: Double

    var conceptID: UUID? { UUID(uuidString: id) }
}

struct PassportSubjectDTO: Decodable, Identifiable, Equatable, Hashable {
    let subjectId: String
    let slug: String
    let name: String
    let icon: String
    let accent: String
    let learned: Int
    let totalTouched: Int
    let progress: Double
    let concepts: [PassportConceptDTO]

    var id: String { subjectId }
}

struct PassportStampDTO: Decodable, Identifiable, Equatable, Hashable {
    let kind: String
    let key: String
    let title: String
    let subtitle: String
    let icon: String
    let earnedAt: Date

    var id: String { "\(kind):\(key)" }
}

struct PassportDTO: Decodable {
    let conceptsCovered: Int
    let conceptsLearned: Int
    let subjects: Int
    let projects: Int
    let sessions: Int
    let subjectCards: [PassportSubjectDTO]
    let stamps: [PassportStampDTO]
}

struct HistoryDayDTO: Decodable, Identifiable, Equatable {
    let date: Date
    let concepts: Int
    let content: Int
    let questions: Int
    let quizzes: Int

    var id: Date { date }
}

struct ProjectDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let skills: [String]
    let status: String
    let progress: Double
    let coverSeed: String
    let createdAt: Date
    let concepts: [ConceptRefDTO]
}

struct ConceptDetailDTO: Decodable {
    let concept: ConceptDTO
    let subject: SubjectDTO?
    let next: [ConceptDTO]
}

// MARK: - Request bodies

struct RegisterBody: Encodable {
    let email: String
    let username: String
    let password: String
    let displayName: String
}

struct LoginBody: Encodable {
    let email: String
    let password: String
}

struct DevSkipBody: Encodable {
    var secret: String = ""
}

struct RefreshBody: Encodable {
    let refreshToken: String
}

struct OnboardingBody: Encodable {
    let stage: String
    let grade: String?
    let curriculum: String?
    let subjectSlugs: [String]
    let learningPreferences: [String]
    let goals: [String]
    let language: String
}

struct AskBody: Encodable {
    let question: String
    let mode: String
    let contentId: String?
    let conceptId: String?
}

struct InteractionBody: Encodable {
    let kind: String
    var contentId: String?
    var conceptId: String?
    var dwellSeconds: Int = 0
}

struct QuizBody: Encodable {
    let conceptId: String
    let count: Int
}

struct QuizAnswerBody: Encodable {
    let questionId: String
    let selectedIndex: Int
}

struct QuizSubmitBody: Encodable {
    let answers: [QuizAnswerBody]
}

struct MarkLearnedBody: Encodable {
    let conceptId: String
}

struct TranslateBody: Encodable {
    let translateTo: String
}

struct ProjectBody: Encodable {
    let title: String
    let description: String
    let skills: [String]
    let conceptIds: [String]
    let status: String
    let progress: Double
}

struct ProfilePatchBody: Encodable {
    var displayName: String?
    var bio: String?
    var subjectSlugs: [String]?
    var learningPreferences: [String]?
    var goals: [String]?
}

struct EmptyBody: Encodable {}
