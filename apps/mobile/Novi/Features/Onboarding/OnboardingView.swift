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
    /// An array, not a set: the order the learner picks subjects in IS the
    /// priority, and the server seeds interest weights from it.
    @State private var subjects: [String] = []
    @State private var weak: [String] = []
    @State private var preferences: Set<String> = []
    @State private var goals: Set<String> = []

    @State private var busy = false
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
        .task { await session.loadSubjects() }
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
        case 2: !subjects.isEmpty
        case 3: !weak.isEmpty
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
                                    grade = option.slug
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
                stepHeading("What are you studying?", "Tap order is priority. The first subject leads your feed.")
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(session.subjects) { subject in
                        let rank = subjects.firstIndex(of: subject.slug)
                        NVChip(
                            text: rank == nil ? subject.name : "\(rank! + 1). \(subject.name)",
                            selected: rank != nil
                        ) {
                            if let rank {
                                subjects.remove(at: rank)
                                weak.removeAll { $0 == subject.slug }
                            } else {
                                subjects.append(subject.slug)
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

    private var weakStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                stepHeading(
                    "Where are you stuck?",
                    "Pick the subjects that feel hardest right now. Novi spends more of the feed, and more care in explanations, here."
                )
                let chosen = session.subjects.filter { subjects.contains($0.slug) }
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(chosen) { subject in
                        NVChip(
                            text: subject.name,
                            selected: weak.contains(subject.slug)
                        ) {
                            if let idx = weak.firstIndex(of: subject.slug) {
                                weak.remove(at: idx)
                            } else {
                                weak.append(subject.slug)
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

    private func advance() {
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
            return
        }
        guard let stage, let grade, !subjects.isEmpty, !weak.isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                try await session.completeOnboarding(
                    OnboardingBody(
                        stage: stage,
                        grade: grade,
                        curriculum: curriculum,
                        subjectSlugs: subjects,
                        weakSubjectSlugs: weak,
                        learningPreferences: Array(preferences),
                        goals: Array(goals),
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
