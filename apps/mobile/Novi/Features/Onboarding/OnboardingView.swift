import SwiftUI

/// Six screens, one question each.
///
/// Grade and the subjects they are stuck on are not optional colour: they are
/// what the ranker and the tutor actually read. Skip-login still lands here
/// until those answers exist — a developer account with no profile is not a
/// personalised feed.
///
/// Nothing is sent until the last step. The API takes the whole questionnaire
/// in one request, so a learner who abandons on step three leaves no
/// half-built profile for the recommender to work from.
struct OnboardingView: View {
    @EnvironmentObject private var session: AppSession

    @State private var step = 0
    @State private var stage: String?
    @State private var grade: String?
    @State private var curriculum: String?
    @State private var gradeMap: GradeCurriculumDTO?
    /// Pick order becomes subject priority on the API.
    @State private var currentCourses: [String] = []
    @State private var courseNames: [String: String] = [:]
    @State private var focusSubjects: [String] = []
    @State private var focusGoals: [String: String] = [:]
    @State private var preferences: Set<String> = []
    @State private var goals: Set<String> = []

    @State private var busy = false
    @State private var loadingCourses = false
    @State private var error: APIError?

    private let totalSteps = 6

    var body: some View {
        ZStack {
            AuroraBackdrop(strength: step == 0 ? 0.34 : 0.08)
                .animation(.easeInOut(duration: 0.5), value: step)

            VStack(spacing: 0) {
            topBar

            TabView(selection: $step) {
                welcomeStep.tag(0)
                schoolStep.tag(1)
                subjectStep.tag(2)
                weakStep.tag(3)
                preferenceStep.tag(4)
                goalStep.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: step)

            if let error {
                Text(error.message)
                    .font(NV.small)
                    .foregroundStyle(NV.error)
                    .padding(.horizontal, NV.pageMargin)
                    .padding(.bottom, 8)
            }

            bottomBar
            }
        }
        .task(id: curriculumKey) { await loadCurriculum() }
    }

    private var topBar: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NV.ink)
                        .frame(width: 36, height: 36)
                }
            }
            Spacer()
            if step > 0 {
                HStack(spacing: 5) {
                    ForEach(1..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? NV.ink900 : NV.track)
                            .frame(width: i == step ? 18 : 7, height: 7)
                    }
                }
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, NV.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: NV.Space.s) {
            NVButton(
                title: step == 0 ? "Let's go" : (step == totalSteps - 1 ? "Start learning" : "Continue"),
                loading: busy,
                enabled: canAdvance
            ) {
                advance()
            }
            .padding(.horizontal, NV.pageMargin)
        }
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: true
        case 1: stage != nil && grade != nil
        case 2: gradeMap != nil && !currentCourses.isEmpty && !loadingCourses
        case 3:
            !focusSubjects.isEmpty
                && focusSubjects.allSatisfy { focusGoals[$0] != nil }
        default: true
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            Spacer()
            Text("Before the feed,")
                .displayStyle(8)
                .foregroundStyle(NV.ink)
            Text("a few things about you.")
                .font(NV.h2)
                .foregroundStyle(NV.inkSecondary)
            Text("Grade, what you study, and where you are stuck. That is what the feed and the tutor are built from — not a generic “for you”.")
                .font(NV.body)
                .foregroundStyle(NV.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, NV.pageMargin)
    }

    private var schoolStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.xl) {
                stepHeading("Where are you in school?", "This sets the level of every explanation.")
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(Onb.stages) { option in
                        NVChip(text: option.label, icon: option.icon, selected: stage == option.slug) {
                            if stage != option.slug {
                                stage = option.slug
                                if let grade, !Onb.grades(for: option.slug).contains(where: { $0.slug == grade }) {
                                    self.grade = nil
                                    resetCourseAnswers()
                                }
                            }
                        }
                    }
                }

                if let stage {
                    VStack(alignment: .leading, spacing: NV.Space.s) {
                        Text("GRADE")
                            .font(NV.caption)
                            .foregroundStyle(NV.inkTertiary)
                        FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                            ForEach(Onb.grades(for: stage)) { option in
                                NVChip(text: option.label, selected: grade == option.slug) {
                                    if grade != option.slug {
                                        grade = option.slug
                                        resetCourseAnswers()
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: NV.Space.s) {
                        Text("CURRICULUM · OPTIONAL")
                            .font(NV.caption)
                            .foregroundStyle(NV.inkTertiary)
                        FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                            ForEach(Onb.curricula) { option in
                                NVChip(text: option.label, selected: curriculum == option.slug) {
                                    curriculum = curriculum == option.slug ? nil : option.slug
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var subjectStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                stepHeading(
                    "Which classes are you taking?",
                    "Choose from your full grade map, then add your school’s exact class name if it differs."
                )

                if loadingCourses {
                    HStack(spacing: NV.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("Loading your grade map…")
                            .font(NV.small).foregroundStyle(NV.inkTertiary)
                    }
                    .padding(.vertical, NV.Space.l)
                } else if let gradeMap {
                    HStack(spacing: NV.Space.s) {
                        NVTag(text: gradeMap.gradeLabel, tint: NV.ink)
                        NVTag(text: gradeMap.ageRange, tint: NV.inkTertiary)
                    }

                    ForEach(["required", "recommended"], id: \.self) { requirement in
                        let courses = gradeMap.courses.filter {
                            $0.requirement == requirement
                        }
                        if !courses.isEmpty {
                            VStack(alignment: .leading, spacing: NV.Space.s) {
                                Text(requirement == "required" ? "GRADE CORE" : "RECOMMENDED")
                                    .font(NV.caption)
                                    .foregroundStyle(NV.inkTertiary)
                                ForEach(courses) { course in
                                    currentCourseCard(course)
                                }
                            }
                        }
                    }
                } else {
                    NVErrorNote(
                        message: "The course map could not be loaded.",
                        retry: { Task { await loadCurriculum() } }
                    )
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var weakStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                stepHeading(
                    "What do you want to strengthen?",
                    "Choose one or more subjects and a concrete outcome. These priorities lead your feed and Passport."
                )

                if let gradeMap {
                    VStack(spacing: NV.Space.s) {
                        ForEach(gradeMap.courses) { course in
                            focusSubjectCard(course)
                        }
                    }
                } else {
                    Text("Choose a grade first.")
                        .font(NV.body).foregroundStyle(NV.inkTertiary)
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func currentCourseCard(_ course: CurriculumCourseDTO) -> some View {
        let selected = currentCourses.contains(course.slug)
        let rank = currentCourses.firstIndex(of: course.slug).map { $0 + 1 }

        return VStack(alignment: .leading, spacing: NV.Space.s) {
            Button {
                if let index = currentCourses.firstIndex(of: course.slug) {
                    currentCourses.remove(at: index)
                    courseNames[course.slug] = nil
                } else {
                    currentCourses.append(course.slug)
                }
            } label: {
                HStack(alignment: .top, spacing: NV.Space.m) {
                    Image(systemName: course.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? NV.spark : NV.inkTertiary)
                        .frame(width: 34, height: 34)
                        .background(selected ? NV.sparkSoft : NV.surfaceSoft)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(course.subjectName)
                                .font(NV.caption).foregroundStyle(NV.inkTertiary)
                            if let rank {
                                Text("CURRENT \(rank)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NV.spark)
                            }
                        }
                        Text(course.name)
                            .font(NV.bodyStrong).foregroundStyle(NV.ink)
                            .multilineTextAlignment(.leading)
                        Text(course.skills.prefix(2).joined(separator: " · "))
                            .font(NV.small).foregroundStyle(NV.inkTertiary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? NV.spark : NV.track)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(course.subjectName)
            .accessibilityIdentifier("onboarding.course.\(course.subjectSlug)")
            .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())

            if selected {
                TextField(
                    course.name,
                    text: Binding(
                        get: { courseNames[course.slug] ?? "" },
                        set: { courseNames[course.slug] = $0 }
                    ),
                    prompt: Text("Exact class name (optional)")
                        .foregroundColor(NV.inkGhost)
                )
                .font(NV.small)
                .foregroundStyle(NV.ink)
                .padding(.horizontal, NV.Space.m)
                .frame(height: 42)
                .background(NV.surface)
                .clipShape(RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous)
                        .strokeBorder(NV.hairline, lineWidth: 1)
                }
            }
        }
        .padding(NV.Space.m)
        .background(
            selected ? NV.sparkSoft.opacity(0.55) : NV.surface,
            in: RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous)
                .strokeBorder(selected ? NV.spark.opacity(0.3) : NV.hairline, lineWidth: 1)
        }
    }

    private func focusSubjectCard(_ course: CurriculumCourseDTO) -> some View {
        let selected = focusSubjects.contains(course.subjectSlug)
        let goal = focusGoals[course.subjectSlug]

        return VStack(alignment: .leading, spacing: NV.Space.s) {
            Button {
                if let index = focusSubjects.firstIndex(of: course.subjectSlug) {
                    focusSubjects.remove(at: index)
                    focusGoals[course.subjectSlug] = nil
                } else {
                    focusSubjects.append(course.subjectSlug)
                }
            } label: {
                HStack(spacing: NV.Space.m) {
                    Image(systemName: course.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? NV.spark : NV.inkTertiary)
                        .frame(width: 34, height: 34)
                        .background(selected ? NV.sparkSoft : NV.surfaceSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.subjectName)
                            .font(NV.bodyStrong).foregroundStyle(NV.ink)
                        Text(currentCourses.contains(course.slug) ? "Current class" : course.name)
                            .font(NV.small).foregroundStyle(NV.inkTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? NV.spark : NV.track)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(course.subjectName)
            .accessibilityIdentifier("onboarding.focus.\(course.subjectSlug)")
            .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())

            if selected {
                Menu {
                    ForEach(Onb.focusGoals) { option in
                        Button {
                            focusGoals[course.subjectSlug] = option.slug
                        } label: {
                            Label(
                                option.label,
                                systemImage: goal == option.slug ? "checkmark" : "circle"
                            )
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GOAL")
                                .font(NV.caption).foregroundStyle(NV.inkTertiary)
                            Text(Onb.focusGoalLabel(goal))
                                .font(NV.smallStrong)
                                .foregroundStyle(goal == nil ? NV.spark : NV.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NV.inkTertiary)
                    }
                    .padding(.horizontal, NV.Space.m)
                    .frame(height: 46)
                    .background(NV.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous))
                }
            }
        }
        .padding(NV.Space.m)
        .background(
            selected ? NV.sparkSoft.opacity(0.55) : NV.surface,
            in: RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous)
                .strokeBorder(selected ? NV.spark.opacity(0.3) : NV.hairline, lineWidth: 1)
        }
    }

    private var preferenceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                stepHeading("How do you like to learn?", "Optional. Skip if you are not sure.")
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(Onb.preferences) { option in
                        NVChip(
                            text: option.label,
                            icon: option.icon,
                            selected: preferences.contains(option.slug)
                        ) {
                            if preferences.contains(option.slug) { preferences.remove(option.slug) }
                            else { preferences.insert(option.slug) }
                        }
                    }
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var goalStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                stepHeading("What are you here for?", "Optional. This colours the tutor, not the feed.")
                VStack(alignment: .leading, spacing: NV.Space.s) {
                    ForEach(Onb.goals) { option in
                        Button {
                            if goals.contains(option.slug) { goals.remove(option.slug) }
                            else { goals.insert(option.slug) }
                        } label: {
                            HStack(alignment: .top, spacing: NV.Space.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).font(NV.bodyStrong).foregroundStyle(NV.ink)
                                    Text(option.detail).font(NV.small).foregroundStyle(NV.inkTertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: goals.contains(option.slug) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(goals.contains(option.slug) ? NV.spark : NV.track)
                            }
                            .padding(NV.Space.m)
                            .cardSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NV.h1)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(NV.body)
                .foregroundStyle(NV.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var curriculumKey: String {
        guard let stage, let grade else { return "" }
        return "\(stage):\(grade)"
    }

    private func resetCourseAnswers() {
        gradeMap = nil
        currentCourses = []
        courseNames = [:]
        focusSubjects = []
        focusGoals = [:]
    }

    private func loadCurriculum() async {
        guard let stage, let grade else { return }
        loadingCourses = true
        defer { loadingCourses = false }
        do {
            let map: GradeCurriculumDTO = try await session.gradeCurriculum(
                stage: stage, grade: grade
            )
            guard self.stage == stage, self.grade == grade else { return }
            gradeMap = map
            error = nil
        } catch let apiError as APIError {
            gradeMap = nil
            error = apiError
        } catch {
            gradeMap = nil
            self.error = APIError.transport(error)
        }
    }

    private func advance() {
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
            return
        }
        guard
            let stage,
            let grade,
            !currentCourses.isEmpty,
            !focusSubjects.isEmpty,
            focusSubjects.allSatisfy({ focusGoals[$0] != nil })
        else { return }
        busy = true
        error = nil
        Task {
            do {
                try await session.completeOnboarding(
                    LearningOnboardingBody(
                        stage: stage,
                        grade: grade,
                        curriculum: curriculum,
                        currentCourses: currentCourses.map { slug in
                            CurrentCourseSelectionDTO(
                                courseSlug: slug,
                                name: courseNames[slug, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        },
                        focusSubjectSlugs: focusSubjects,
                        focusGoals: focusGoals,
                        learningPreferences: preferences.sorted(),
                        goals: goals.sorted(),
                        language: "en"
                    )
                )
            } catch let e as APIError {
                error = e
            } catch {
                self.error = APIError.transport(error)
            }
            busy = false
        }
    }
}
