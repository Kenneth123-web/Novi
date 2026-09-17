import SwiftUI

/// The Learning Passport — the record of what the learner has actually done.
///
/// Styled as a document rather than a dashboard: a header block with the
/// counts, then a stamp collection, then a page per subject. It is the one
/// screen meant to be worth opening for its own sake.
struct PassportView: View {
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @StateObject private var chrome = Chrome()
    @State private var passport: PassportDTO?
    @State private var error: APIError?
    @State private var path = NavigationPath()
    @State private var quizConcept: QuizTarget?
    @State private var poster: PosterImage?
    @State private var rendering = false
    @State private var editingProfile = false
    @State private var expandedCourses: Set<String> = []

    private struct QuizTarget: Identifiable {
        let id: UUID
        let name: String
    }

    /// `ShareLink` needs something `Identifiable` to drive a sheet, and a bare
    /// `UIImage` is not.
    private struct PosterImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.xl) {
                    if let passport {
                        cover(passport)
                        if let curriculum = passport.curriculum, !passport.courseMap.isEmpty {
                            curriculumHeader(curriculum, passport: passport)
                            courseSections(passport.courseMap)
                        } else {
                            customizationEmpty
                        }
                        if !passport.stamps.isEmpty { stamps(passport) }
                        if passport.subjectCards.isEmpty && passport.courseMap.isEmpty {
                            NVEmptyState(
                                icon: "checkmark.seal",
                                title: "No stamps yet",
                                message: "Open a concept, ask a question, or take a quiz — everything you learn lands here.",
                                actionTitle: "Ask something",
                                action: { onAsk(AskSeed(question: "", autoSubmit: false)) }
                            )
                            .padding(.top, NV.Space.xl)
                        } else if !passport.subjectCards.isEmpty {
                            subjects(passport)
                        }
                    } else if let error {
                        NVErrorNote(message: error.message, retry: { Task { await load() } })
                    } else {
                        skeleton
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, NV.Space.l)
                .padding(.top, NV.Space.s)
            }
            .background(NV.page)
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .navigationTitle("Passport")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        makePoster()
                    } label: {
                        if rendering {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(NV.ink)
                        }
                    }
                    .disabled(passport == nil || rendering)
                }
            }
            .sheet(item: $poster) { item in
                ShareSheet(items: [item.image])
            }
            .sheet(isPresented: $editingProfile, onDismiss: {
                Task { await load() }
            }) {
                LearningProfileEditor()
            }
            .navigationDestination(for: RelatedConceptDTO.self) { concept in
                ConceptView(conceptID: concept.conceptID, fallbackName: concept.name,
                            chrome: chrome, onAsk: onAsk)
            }
            .sheet(item: $quizConcept) { target in
                QuizView(conceptID: target.id, conceptName: target.name)
            }
            .task(id: session.profile) { await load() }
        }
    }

    /// The cover reads as a document, not a dashboard.
    ///
    /// Deep ink rather than the accent: a full-bleed violet panel is a
    /// dashboard header, and this is meant to be the one screen worth opening
    /// for its own sake. The concentric rules are the guilloché a real
    /// passport prints to make itself hard to forge — here they are just what
    /// stops a dark rectangle from looking like an empty state.
    private func cover(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            VStack(alignment: .leading, spacing: NV.Space.xs) {
                Text("LEARNING PASSPORT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.52))
                Text(session.user?.displayName ?? "")
                    .displayStyle(8)
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 0) {
                stat("\(passport.conceptsCovered)", "CONCEPTS")
                stat("\(passport.conceptsLearned)", "LEARNED")
                stat("\(passport.subjects)", "SUBJECTS")
                stat("\(passport.sessions)", "SESSIONS")
            }
        }
        .padding(NV.Space.xl - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0x24272E), NV.ink950, NV.ink900],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // Guilloché. Clipped by the card's own shape below, so the
                // rings can run off the corner instead of being tucked inside
                // it — a ring that stops short of the edge reads as a sticker.
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    .frame(width: 210, height: 210)
                    .offset(x: 50, y: -50)
                Circle()
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .offset(x: 24, y: -24)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [NV.spark.opacity(0.40), NV.spark.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .offset(x: 24, y: -8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NV.Radius.hero, style: .continuous))
        .shadow(color: NV.ink900.opacity(0.18), radius: 20, x: 0, y: 10)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(NV.step(5, .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stamps(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Stamps", subtitle: "\(passport.stamps.count) earned")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NV.Space.m) {
                    ForEach(passport.stamps) { stamp in
                        StampBadge(
                            title: stamp.title,
                            subtitle: stamp.subtitle,
                            icon: stamp.icon,
                            tint: stamp.kind == "milestone" ? NV.warning : NV.spark
                        )
                    }
                }
                .padding(.vertical, NV.Space.s)
                .padding(.horizontal, 2)
            }
        }
    }

    private func subjects(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Subjects")
            ForEach(passport.subjectCards) { card in
                VStack(alignment: .leading, spacing: NV.Space.m) {
                    HStack(spacing: NV.Space.s) {
                        Image(systemName: card.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NV.spark)
                        Text(card.name).font(NV.h3).foregroundStyle(NV.ink)
                        Spacer(minLength: 0)
                        Text("\(card.learned)/\(card.totalTouched)")
                            .font(NV.caption).foregroundStyle(NV.inkTertiary)
                    }

                    NVProgressBar(value: card.progress)

                    VStack(spacing: 0) {
                        ForEach(card.concepts) { concept in
                            conceptRow(concept)
                        }
                    }
                }
                .padding(NV.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private func conceptRow(_ concept: PassportConceptDTO) -> some View {
        HStack(spacing: NV.Space.s) {
            Image(systemName: iconFor(concept.mastery))
                .font(.system(size: 13))
                .foregroundStyle(NV.mastery(concept.mastery))
                .frame(width: 18)

            NavigationLink(value: RelatedConceptDTO(
                name: concept.name, id: concept.id, slug: concept.slug
            )) {
                Text(concept.name)
                    .font(NV.small)
                    .foregroundStyle(NV.ink)
            }
            .buttonStyle(.plain)

            Spacer(minLength: NV.Space.s)

            Text(concept.mastery.capitalized)
                .font(NV.caption)
                .foregroundStyle(NV.mastery(concept.mastery))

            // The next action is on the row, so improving a weak concept never
            // requires navigating away to find the button.
            if concept.mastery != "mastered", let id = concept.conceptID {
                Button {
                    quizConcept = QuizTarget(id: id, name: concept.name)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(NV.spark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .hairline(.bottom, color: NV.hairline.opacity(0.6))
    }

    private func iconFor(_ mastery: String) -> String {
        switch mastery {
        case "mastered": return "seal.fill"
        case "learned": return "checkmark.seal.fill"
        case "practiced": return "checkmark.circle.fill"
        case "explored": return "circle.lefthalf.filled"
        case "viewed": return "circle.dotted"
        default: return "circle"
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            NVSkeleton(height: 128)
            NVSkeleton(height: 16, width: 120)
            NVSkeleton(height: 96)
            NVSkeleton(height: 140)
        }
    }

    /// Renders on a detached task hop so the button's spinner actually paints
    /// before the render begins. `ImageRenderer` is synchronous and main-actor
    /// only, so without yielding first the UI freezes on the tap and the
    /// spinner is never seen.
    private func makePoster() {
        guard let passport, !rendering else { return }
        rendering = true
        Task {
            await Task.yield()
            let image = PassportPosterRenderer.render(
                passport: passport,
                name: session.user?.displayName ?? "Novi learner"
            )
            rendering = false
            if let image { poster = PosterImage(image: image) }
        }
    }

    private func load() async {
        do {
            passport = try await session.api.authed(.get, "passport", as: PassportDTO.self)
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
    }

    // MARK: Grade course map

    /// Running head in the document voice: tiny, letterspaced, quiet — the
    /// same register Travelers uses on a passport leaf, applied to a grade.
    private func curriculumHeader(
        _ curriculum: PassportCurriculumContextDTO,
        passport: PassportDTO
    ) -> some View {
        let currentCount = passport.courseMap.filter(\.isCurrent).count
        let focusCount = passport.courseMap.filter(\.isFocus).count
        return VStack(alignment: .leading, spacing: NV.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(curriculum.gradeLabel.uppercased()) · \(curriculum.ageRange.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(NV.inkTertiary)
                    NVSectionHeader(
                        title: "Course map",
                        subtitle: "\(passport.courseMap.count) courses · \(currentCount) current · \(focusCount) focus",
                        action: ("Customize", { editingProfile = true })
                    )
                }
            }

            if let framework = curriculum.framework, !framework.isEmpty {
                HStack(spacing: NV.Space.s) {
                    NVTag(text: framework, tint: NV.spark)
                    Text(curriculum.frameworkNote)
                        .font(NV.caption)
                        .foregroundStyle(NV.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(curriculum.frameworkNote)
                    .font(NV.caption)
                    .foregroundStyle(NV.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if curriculum.selectionSource == "inferred" {
                Text("Recovered from the subjects you picked earlier. Edit to name the exact classes you take.")
                    .font(NV.small)
                    .foregroundStyle(NV.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("passport.curriculum")
    }

    private func courseSections(_ courses: [PassportCourseDTO]) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.xl) {
            ForEach(PassportCourseSection.allCases, id: \.self) { section in
                let items = courses.filter { $0.section == section }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: NV.Space.m) {
                        NVSectionHeader(title: section.title, subtitle: section.subtitle)
                        ForEach(items) { course in
                            courseCard(course)
                        }
                    }
                }
            }
        }
    }

    private func courseCard(_ course: PassportCourseDTO) -> some View {
        let expanded = expandedCourses.contains(course.slug)
        return VStack(alignment: .leading, spacing: NV.Space.m) {
            Button {
                if expanded {
                    expandedCourses.remove(course.slug)
                } else {
                    expandedCourses.insert(course.slug)
                }
            } label: {
                VStack(alignment: .leading, spacing: NV.Space.s) {
                    HStack(alignment: .top, spacing: NV.Space.m) {
                        Image(systemName: course.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NV.spark)
                            .frame(width: 34, height: 34)
                            .background(NV.sparkSoft)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.subjectName)
                                .font(NV.caption)
                                .foregroundStyle(NV.inkTertiary)
                            Text(course.name)
                                .font(NV.bodyStrong)
                                .foregroundStyle(NV.ink)
                                .multilineTextAlignment(.leading)
                            if course.name != course.canonicalName {
                                Text(course.canonicalName)
                                    .font(NV.caption)
                                    .foregroundStyle(NV.inkTertiary)
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 4) {
                            laneBadge(course)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NV.inkGhost)
                        }
                    }

                    Text(course.description)
                        .font(NV.small)
                        .foregroundStyle(NV.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    FlowRow(spacing: 6, lineSpacing: 6) {
                        ForEach(course.skills, id: \.self) { skill in
                            NVTag(text: skill, tint: NV.inkTertiary)
                        }
                    }

                    if !course.focusAreas.isEmpty {
                        FlowRow(spacing: 6, lineSpacing: 6) {
                            ForEach(course.focusAreas) { area in
                                NVTag(text: area.name, icon: "scope", tint: NV.spark)
                            }
                        }
                    }

                    HStack(spacing: NV.Space.s) {
                        Image(systemName: course.statusIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NV.mastery(course.status == "not_started" ? "viewed" : course.status))
                        Text(course.statusLabel)
                            .font(NV.caption)
                            .foregroundStyle(NV.inkSecondary)
                        Spacer(minLength: 0)
                        if course.totalConcepts > 0 {
                            Text("\(course.learnedConcepts)/\(course.totalConcepts) learned")
                                .font(NV.caption)
                                .foregroundStyle(NV.inkTertiary)
                        }
                    }
                    NVProgressBar(value: course.progress, tint: course.isFocus ? NV.spark : NV.ink900)

                    Text(course.recommendationReason)
                        .font(NV.caption)
                        .foregroundStyle(NV.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let goal = course.focusGoal {
                        NVTag(text: goal, icon: "target", tint: NV.spark)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, !course.concepts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(course.concepts) { concept in
                        courseConceptRow(concept)
                    }
                }
            } else if expanded, course.concepts.isEmpty {
                Text("No linked concepts yet for this course.")
                    .font(NV.small)
                    .foregroundStyle(NV.inkTertiary)
            }
        }
        .padding(NV.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityIdentifier("passport.course.\(course.slug)")
    }

    private func courseConceptRow(_ concept: PassportCourseConceptDTO) -> some View {
        HStack(spacing: NV.Space.s) {
            Image(systemName: iconFor(concept.mastery))
                .font(.system(size: 13))
                .foregroundStyle(NV.mastery(concept.mastery))
                .frame(width: 18)

            NavigationLink(value: RelatedConceptDTO(
                name: concept.name, id: concept.id, slug: concept.slug
            )) {
                Text(concept.name)
                    .font(NV.small)
                    .foregroundStyle(NV.ink)
            }
            .buttonStyle(.plain)

            Spacer(minLength: NV.Space.s)

            Text(concept.mastery.capitalized)
                .font(NV.caption)
                .foregroundStyle(NV.mastery(concept.mastery))

            if concept.mastery != "mastered", let id = concept.conceptID {
                Button {
                    quizConcept = QuizTarget(id: id, name: concept.name)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(NV.spark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .hairline(.bottom, color: NV.hairline.opacity(0.6))
    }

    private func laneBadge(_ course: PassportCourseDTO) -> some View {
        let tint: Color
        switch course.section {
        case .focus: tint = NV.spark
        case .current: tint = NV.ink
        case .required: tint = NV.inkSecondary
        case .recommended: tint = NV.inkTertiary
        }
        return NVTag(text: course.section.title, tint: tint, filled: course.section == .focus)
    }

    private var customizationEmpty: some View {
        NVEmptyState(
            icon: "rectangle.and.pencil.and.ellipsis",
            title: "No grade map yet",
            message: "Tell Novi your grade, the classes you take, and what you want to strengthen. The passport is built from those answers — not a generic list.",
            actionTitle: "Customize learning",
            action: { editingProfile = true }
        )
        .padding(.vertical, NV.Space.l)
        .accessibilityIdentifier("passport.customizationEmpty")
    }
}
