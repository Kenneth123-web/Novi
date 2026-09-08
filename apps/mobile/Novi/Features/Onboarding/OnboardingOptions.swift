import Foundation

/// The questionnaire's answer sets.
///
/// The `slug` on every option is what the API validates against and what the
/// interest map is keyed by. Keeping the pair together here — rather than
/// letting each view write its own string — is what stops a relabelled option
/// from silently becoming a value the server rejects at the final step.
enum Onb {
    struct Option: Identifiable, Hashable {
        let slug: String
        let label: String
        var detail: String = ""
        var icon: String = ""
        var id: String { slug }
    }

    static let stages: [Option] = [
        .init(slug: "middle", label: "Middle school", icon: "book"),
        .init(slug: "high", label: "High school", icon: "graduationcap"),
        .init(slug: "college", label: "College", icon: "building.columns"),
        .init(slug: "other", label: "Something else", icon: "sparkles"),
    ]

    static let curricula: [Option] = [
        .init(slug: "AP", label: "AP"),
        .init(slug: "IB", label: "IB"),
        .init(slug: "SAT", label: "SAT"),
        .init(slug: "ACT", label: "ACT"),
        .init(slug: "GCSE", label: "GCSE"),
        .init(slug: "A-Level", label: "A-Level"),
        .init(slug: "Gaokao", label: "Gaokao"),
        .init(slug: "Other", label: "Other"),
    ]

    static let preferences: [Option] = [
        .init(slug: "short_video", label: "Short videos", icon: "play.rectangle"),
        .init(slug: "long_explanation", label: "Long explanations", icon: "text.alignleft"),
        .init(slug: "visual", label: "Visual explanations", icon: "photo"),
        .init(slug: "real_world", label: "Real-world examples", icon: "globe"),
        .init(slug: "tutorials", label: "Tutorials", icon: "list.number"),
        .init(slug: "projects", label: "Projects", icon: "hammer"),
        .init(slug: "discussions", label: "Discussions", icon: "bubble.left.and.bubble.right"),
        .init(slug: "news", label: "News", icon: "newspaper"),
        .init(slug: "case_studies", label: "Case studies", icon: "doc.text.magnifyingglass"),
        .init(slug: "practice", label: "Practice questions", icon: "checkmark.circle"),
    ]

    static let goals: [Option] = [
        .init(slug: "improve_grades", label: "Improve my grades",
              detail: "Shore up what I've already been taught"),
        .init(slug: "exam_prep", label: "Prepare for exams",
              detail: "There's a date in the calendar"),
        .init(slug: "learn_new", label: "Learn something new",
              detail: "Outside what school covers"),
        .init(slug: "build_projects", label: "Build projects",
              detail: "Learn it by making something"),
        .init(slug: "explore_careers", label: "Explore careers",
              detail: "Work out what this leads to"),
        .init(slug: "go_deeper", label: "Go deeper in a subject",
              detail: "Past where the syllabus stops"),
        .init(slug: "college_prep", label: "Prepare for college",
              detail: "Get ahead of the first year"),
        .init(slug: "curiosity", label: "Personal curiosity",
              detail: "No particular reason"),
    ]
}
