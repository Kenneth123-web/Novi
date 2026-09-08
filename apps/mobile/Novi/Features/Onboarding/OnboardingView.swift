import SwiftUI

/// Five screens, one question each.
///
/// One question per screen rather than one long form: these answers are what
/// the entire feed is built from, and a scrolling wall of thirty checkboxes
/// gets skimmed and half-answered. The cost is five taps, and the step bar is
/// there so those five are visibly finite.
///
/// Nothing is sent until the last step. The API takes the whole questionnaire
/// in one request, so a learner who abandons on step three leaves no
/// half-built profile for the recommender to work from.
struct OnboardingView: View {
    @EnvironmentObject private var session: AppSession

    @State private var step = 0
    @State private var stage: String?
    @State private var grade = ""
    @State private var curriculum: String?
    /// An array, not a set: the order the learner picks subjects in IS the
    /// priority, and the server seeds interest weights from it.
    @State private var subjects: [String] = []
    @State private var preferences: Set<String> = []
    @State private var goals: Set<String> = []

    @State private var busy = false
    @State private var error: APIError?

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $step) {
                welcomeStep.tag(0)
                stageStep.tag(1)
                subjectStep.tag(2)
                preferenceStep.tag(3)
                goalStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // The page style is for the transition, not the gesture: swiping
            // past an unanswered question would skip a required answer, so
            // paging is driven only by the button.
            .disabled(busy)

            footer
        }
        .background(NV.surface)
        .task { await session.loadSubjects() }
    }

    private var topBar: some View {
        VStack(spacing: NV.Space.m) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NV.ink)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(step + 1) / \(totalSteps)")
                    .font(NV.caption)
                    .foregroundStyle(NV.inkFaint)
            }
            .frame(height: 24)

            NVStepBar(step: step, total: totalSteps)
        }
        .padding(.horizontal, NV.Space.xl)
        .padding(.top, NV.Space.s)
        .padding(.bottom, NV.Space.l)
    }

    private var footer: some View {
        VStack(spacing: NV.Space.m) {
            if let error {
                NVErrorNote(message: error.message, retry: error.isRetryable ? advance : nil)
            }
            NVButton(
                title: step == 0 ? "Get started" : (step == totalSteps - 1 ? "Start learning" : "Continue"),
                loading: busy,
                enabled: canAdvance,
                action: advance
            )
        }
        .padding(.horizontal, NV.Space.xl)
        .padding(.bottom, NV.Space.l)
    }

    // MARK: Steps

    private func page<Content: View>(
        _ title: String, _ subtitle: String, @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                VStack(alignment: .leading, spacing: NV.Space.s) {
                    Text(title).font(NV.h1).foregroundStyle(NV.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(NV.small).foregroundStyle(NV.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
                Spacer(minLength: NV.Space.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NV.Space.xl)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            Spacer()
            Text("Welcome to your\nlearning world.")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Five quick questions, and your feed stops being random.")
                .font(NV.body)
                .foregroundStyle(NV.inkSoft)

            VStack(alignment: .leading, spacing: NV.Space.m) {
                promise("sparkles", "Ask anything", "An AI tutor that knows your level")
                promise("safari", "Follow the thread", "Videos, posts and discussions on one idea")
                promise("checkmark.seal", "Keep what you learn", "A passport of every concept you master")
            }
            .padding(.top, NV.Space.s)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, NV.Space.xl)
    }

    private func promise(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: NV.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NV.accent)
                .frame(width: 34, height: 34)
                .background(NV.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(NV.bodyStrong).foregroundStyle(NV.ink)
                Text(detail).font(NV.small).foregroundStyle(NV.inkFaint)
            }
        }
    }

    private var stageStep: some View {
        page("What do you study?", "This sets where explanations start.") {
            VStack(spacing: NV.Space.m) {
                cards(Onb.stages, selection: stage.map { [$0] } ?? []) { stage = $0 }

                if stage != nil {
                    VStack(alignment: .leading, spacing: NV.Space.s) {
                        Text("Exam system").font(NV.h3).foregroundStyle(NV.ink)
                        Text("Optional — it tunes the level, not the subjects.")
                            .font(NV.small).foregroundStyle(NV.inkFaint)
                        FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                            ForEach(Onb.curricula) { option in
                                NVChip(text: option.label, selected: curriculum == option.slug) {
                                    curriculum = curriculum == option.slug ? nil : option.slug
                                }
                            }
                        }
                    }
                    .padding(.top, NV.Space.s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: stage)
        }
    }

    private var subjectStep: some View {
        page(
            "What do you want to learn?",
            subjects.isEmpty
                ? "Pick as many as you like. Tap order is priority."
                : "Priority: \(subjectNames)"
        ) {
            if session.subjects.isEmpty {
                VStack(spacing: NV.Space.s) {
                    ForEach(0..<4, id: \.self) { _ in NVSkeleton(height: 38) }
                }
            } else {
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(session.subjects) { subject in
                        let rank = subjects.firstIndex(of: subject.slug)
                        NVChip(
                            text: rank == nil ? subject.name : "\(rank! + 1). \(subject.name)",
                            selected: rank != nil
                        ) {
                            toggleSubject(subject.slug)
                        }
                    }
                }
            }
        }
    }

    private var preferenceStep: some View {
        page("How do you like to learn?", "Your feed leans towards what you pick.") {
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(Onb.preferences) { option in
                    NVChip(
                        text: option.label, icon: option.icon,
                        selected: preferences.contains(option.slug)
                    ) {
                        toggle(option.slug, in: &preferences)
                    }
                }
            }
        }
    }

    private var goalStep: some View {
        page("What are you trying to achieve?", "Pick any that fit.") {
            cards(Onb.goals, selection: goals) { toggle($0, in: &goals) }
        }
    }

    private func cards(
        _ options: [Onb.Option], selection: Set<String>, onTap: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: NV.Space.s) {
            ForEach(options) { option in
                let on = selection.contains(option.slug)
                Button { onTap(option.slug) } label: {
                    HStack(spacing: NV.Space.m) {
                        if !option.icon.isEmpty {
                            Image(systemName: option.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(on ? NV.accent : NV.inkFaint)
                                .frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(NV.bodyStrong).foregroundStyle(NV.ink)
                            if !option.detail.isEmpty {
                                Text(option.detail).font(NV.caption).foregroundStyle(NV.inkFaint)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(on ? NV.accent : NV.inkGhost)
                    }
                    .padding(NV.Space.l)
                    .background(NV.surface, in: RoundedRectangle(cornerRadius: NV.Radius.card,
                                                                 style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous)
                            .stroke(on ? NV.accent : NV.hairline, lineWidth: on ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.12), value: selection)
    }

    // MARK: Logic

    private var subjectNames: String {
        subjects
            .compactMap { slug in session.subjects.first { $0.slug == slug }?.name }
            .joined(separator: " · ")
    }

    private func toggleSubject(_ slug: String) {
        if let index = subjects.firstIndex(of: slug) {
            subjects.remove(at: index)
        } else {
            subjects.append(slug)
        }
    }

    private func toggle(_ slug: String, in set: inout Set<String>) {
        if set.contains(slug) { set.remove(slug) } else { set.insert(slug) }
    }

    /// Only stage and subjects are required. Making all five mandatory turns
    /// an optional preference into a wall, and the recommender has sensible
    /// defaults for the rest.
    private var canAdvance: Bool {
        switch step {
        case 1: return stage != nil
        case 2: return !subjects.isEmpty
        default: return true
        }
    }

    private func advance() {
        guard canAdvance else { return }
        error = nil
        guard step == totalSteps - 1 else {
            withAnimation { step += 1 }
            return
        }
        guard let stage else { return }

        busy = true
        Task {
            do {
                try await session.completeOnboarding(
                    OnboardingBody(
                        stage: stage,
                        grade: grade.isEmpty ? nil : grade,
                        curriculum: curriculum,
                        subjectSlugs: subjects,
                        learningPreferences: Array(preferences),
                        goals: Array(goals),
                        language: "en"
                    )
                )
            } catch let apiError as APIError {
                error = apiError
            } catch {
                self.error = APIError.transport(error)
            }
            busy = false
        }
    }
}
