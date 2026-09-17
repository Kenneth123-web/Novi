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

    /// Must match `GRADES_BY_STAGE` on the API. A label the server would
    /// reject cannot appear as a chip.
    static func grades(for stage: String) -> [Option] {
        switch stage {
        case "middle":
            ["6", "7", "8"].map { .init(slug: $0, label: "Grade \($0)") }
        case "high":
            ["9", "10", "11", "12"].map { .init(slug: $0, label: "Grade \($0)") }
        case "college":
            [
                .init(slug: "freshman", label: "Freshman"),
                .init(slug: "sophomore", label: "Sophomore"),
                .init(slug: "junior", label: "Junior"),
                .init(slug: "senior", label: "Senior"),
                .init(slug: "grad", label: "Graduate"),
            ]
        case "other":
            [
                .init(slug: "adult", label: "Adult learner"),
                .init(slug: "self-taught", label: "Self-taught"),
            ]
        default:
            []
        }
    }

    static func gradeLabel(_ slug: String) -> String {
        for stage in stages {
            if let match = grades(for: stage.slug).first(where: { $0.slug == slug }) {
                return match.label
            }
        }
        return slug
    }

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

    /// A goal is attached to each focus subject, not to the profile in the
    /// abstract. The API serves the same slugs from /onboarding/options.
    static let focusGoals: [Option] = [
        .init(slug: "build_foundations", label: "Build foundations",
              detail: "Repair prerequisite gaps first"),
        .init(slug: "catch_up", label: "Catch up",
              detail: "Get back in step with class"),
        .init(slug: "improve_grades", label: "Improve grades",
              detail: "Turn understanding into results"),
        .init(slug: "exam_readiness", label: "Prepare for an exam",
              detail: "Practice recall, timing and patterns"),
        .init(slug: "get_ahead", label: "Get ahead",
              detail: "Preview what comes next"),
        .init(slug: "build_confidence", label: "Build confidence",
              detail: "Make the subject feel manageable"),
    ]

    static func focusGoalLabel(_ slug: String?) -> String {
        guard let slug else { return "Choose a goal" }
        return focusGoals.first { $0.slug == slug }?.label ?? "Choose a goal"
    }

    /// Must match `SUBJECT_AREAS` on the API. A chip the server would reject
    /// cannot appear here.
    static func areas(for subject: String) -> [Option] {
        areasBySubject[subject] ?? []
    }

    static let areasBySubject: [String: [Option]] = [
        "mathematics": [
            .init(slug: "algebra", label: "Algebra",
                  detail: "Equations, functions and the language of symbols."),
            .init(slug: "geometry", label: "Geometry & trig",
                  detail: "Shape, space and trigonometric ratios."),
            .init(slug: "calculus", label: "Calculus",
                  detail: "Limits, rates of change and accumulation."),
            .init(slug: "statistics", label: "Statistics & probability",
                  detail: "Chance, distributions and inference."),
            .init(slug: "linear-algebra", label: "Linear algebra",
                  detail: "Matrices and eigenvalues."),
        ],
        "physics": [
            .init(slug: "mechanics", label: "Mechanics",
                  detail: "Motion, forces, energy and gravity."),
            .init(slug: "waves-optics", label: "Waves & optics",
                  detail: "Oscillations, light and images."),
            .init(slug: "electricity", label: "Electricity & magnetism",
                  detail: "Fields, circuits and magnetic effects."),
            .init(slug: "thermodynamics", label: "Thermodynamics",
                  detail: "Heat, entropy and the laws that bind them."),
            .init(slug: "modern", label: "Modern physics",
                  detail: "Relativity and the quantum scale."),
        ],
        "chemistry": [
            .init(slug: "structure", label: "Structure & bonding",
                  detail: "Atoms, the periodic table and how atoms stick."),
            .init(slug: "reactions", label: "Reactions & energy",
                  detail: "What happens, how fast, and how far."),
            .init(slug: "organic", label: "Organic chemistry",
                  detail: "Carbon skeletons, groups and mechanisms."),
        ],
        "biology": [
            .init(slug: "cells", label: "Cells & energy",
                  detail: "What a cell is, and how it powers itself."),
            .init(slug: "genetics", label: "Genetics",
                  detail: "DNA, inheritance and protein-making."),
            .init(slug: "physiology", label: "Physiology",
                  detail: "How organisms keep themselves running."),
            .init(slug: "ecology", label: "Evolution & ecology",
                  detail: "Populations, selection and ecosystems."),
        ],
        "computer-science": [
            .init(slug: "programming", label: "Programming",
                  detail: "The constructs you write code with."),
            .init(slug: "algorithms", label: "Algorithms",
                  detail: "Complexity, data structures and problem-solving."),
            .init(slug: "systems", label: "Systems",
                  detail: "How software talks to data and the network."),
            .init(slug: "ai-ml", label: "AI & machine learning",
                  detail: "Networks, embeddings and recommenders."),
        ],
        "economics": [
            .init(slug: "micro", label: "Microeconomics",
                  detail: "Choices, markets and strategic behaviour."),
            .init(slug: "macro", label: "Macroeconomics",
                  detail: "The whole economy: output, prices, policy."),
        ],
        "history": [
            .init(slug: "methods", label: "Historical method",
                  detail: "Sources, and the arguments historians have about them."),
            .init(slug: "revolutions", label: "Revolutions",
                  detail: "Industrial and political ruptures."),
            .init(slug: "twentieth-century", label: "The twentieth century",
                  detail: "World wars, the Cold War and decolonisation."),
        ],
        "geography": [
            .init(slug: "physical", label: "Physical geography",
                  detail: "Earth systems: rock, water, weather."),
            .init(slug: "human", label: "Human geography",
                  detail: "People, cities and a changing climate."),
        ],
        "psychology": [
            .init(slug: "methods", label: "Research methods",
                  detail: "How psychologists actually find things out."),
            .init(slug: "cognition", label: "Cognition",
                  detail: "Memory and the shortcuts minds take."),
            .init(slug: "learning", label: "Learning",
                  detail: "Conditioning and how behaviour changes."),
            .init(slug: "development", label: "Mind & body",
                  detail: "Attachment and the stress response."),
        ],
        "languages": [
            .init(slug: "grammar", label: "Grammar",
                  detail: "Word order, tense and conditionals."),
            .init(slug: "usage", label: "Usage",
                  detail: "Collocations and the right register."),
        ],
        "literature": [
            .init(slug: "reading", label: "Close reading",
                  detail: "Voice, image and what a text is doing."),
            .init(slug: "writing", label: "Writing about texts",
                  detail: "A thesis, then an essay that holds."),
        ],
        "art": [
            .init(slug: "studio", label: "Studio practice",
                  detail: "Composition, colour and drawing in space."),
            .init(slug: "design", label: "Design",
                  detail: "Type, and how to talk about visual work."),
        ],
        "business": [
            .init(slug: "strategy", label: "Strategy & marketing",
                  detail: "How a firm is built and how it finds customers."),
            .init(slug: "finance", label: "Finance",
                  detail: "Unit economics and the statements behind them."),
        ],
        "engineering": [
            .init(slug: "mechanics", label: "Mechanics",
                  detail: "Forces in real objects, and what they do to materials."),
            .init(slug: "electrical", label: "Electrical systems",
                  detail: "Circuits and the loops that control them."),
            .init(slug: "design", label: "Design & CAD",
                  detail: "Drawing the thing before you build it."),
        ],
    ]
}
