import SwiftUI

/// Profile: who you are, what you saved, what you've been doing, and the one
/// setting that matters — the interests the feed is built from.
struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @State private var saved: [ContentDTO] = []
    @State private var history: [HistoryDayDTO] = []
    @State private var gradeMap: GradeCurriculumDTO?
    @State private var editingProfile = false
    @State private var path = NavigationPath()
    @StateObject private var chrome = Chrome()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.xl) {
                    header
                    if !history.isEmpty { activity }
                    interests
                    savedSection
                    signOut
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, NV.pageMargin)
                .padding(.top, NV.Space.s)
            }
            .background(NV.page)
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .navigationTitle("Profile")
            .navigationDestination(for: ContentDTO.self) { content in
                ContentDetailView(contentID: content.id, chrome: chrome, onAsk: { _ in })
            }
            .sheet(isPresented: $editingProfile, onDismiss: {
                Task { await load() }
            }) {
                LearningProfileEditor()
            }
            .task { await load() }
        }
    }

    private var header: some View {
        HStack(spacing: NV.Space.m) {
            Avatar(name: session.user?.avatarSeed ?? "novi", size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.user?.displayName ?? "")
                    .font(NV.h2).foregroundStyle(NV.ink)
                Text("@\(session.user?.username ?? "")")
                    .font(NV.small).foregroundStyle(NV.inkTertiary)
                if let profile = session.profile {
                    HStack(spacing: 5) {
                        if let stage = profile.stage {
                            NVTag(text: stageLabel(stage), tint: NV.spark)
                        }
                        if let grade = profile.grade, !grade.isEmpty {
                            NVTag(text: Onb.gradeLabel(grade), tint: NV.inkTertiary)
                        }
                        if let curriculum = profile.curriculum {
                            NVTag(text: curriculum, tint: NV.inkTertiary)
                        }
                    }
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stageLabel(_ stage: String) -> String {
        ["middle": "Middle school", "high": "High school",
         "college": "College", "other": "Self-directed"][stage] ?? stage
    }

    /// Fourteen days of activity as a small bar chart. Bars are relative to
    /// the busiest day, so a quiet week still shows shape rather than looking
    /// like a flat line.
    private var activity: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Recent activity")
            let peak = max(1, history.map { $0.content + $0.questions + $0.quizzes }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(history.reversed()) { day in
                    let total = day.content + day.questions + day.quizzes
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(total > 0 ? NV.spark : NV.track)
                            .frame(height: max(4, CGFloat(total) / CGFloat(peak) * 56))
                        Text(dayLabel(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(NV.inkGhost)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 74, alignment: .bottom)
            .padding(NV.Space.m)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var interests: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(
                title: "Learning customization",
                subtitle: "Courses, priorities and goals",
                action: ("Edit", { editingProfile = true })
            )
            if let profile = session.profile {
                if !profile.currentCourses.isEmpty {
                    Text("CURRENT COURSES")
                        .font(NV.caption)
                        .foregroundStyle(NV.inkTertiary)
                    VStack(spacing: NV.Space.s) {
                        ForEach(profile.currentCourses, id: \.courseSlug) { selection in
                            let course = gradeMap?.courses.first {
                                $0.slug == selection.courseSlug
                            }
                            HStack(spacing: NV.Space.m) {
                                Image(systemName: course?.icon ?? "book")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NV.spark)
                                    .frame(width: 32, height: 32)
                                    .background(NV.sparkSoft)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        selection.name.isEmpty
                                            ? course?.name ?? "Current course"
                                            : selection.name
                                    )
                                    .font(NV.smallStrong).foregroundStyle(NV.ink)
                                    Text(course?.subjectName ?? selection.courseSlug)
                                        .font(NV.caption).foregroundStyle(NV.inkTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(NV.Space.m)
                            .edgedSurface()
                        }
                    }
                }

                if !profile.weakSubjects.isEmpty {
                    Text("FOCUS")
                        .font(NV.caption)
                        .foregroundStyle(NV.inkTertiary)
                    FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                        ForEach(profile.weakSubjects, id: \.self) { slug in
                            let name = session.subjects.first { $0.slug == slug }?.name ?? slug
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(NV.smallStrong)
                                Text(Onb.focusGoalLabel(profile.focusGoals[slug]))
                                    .font(NV.caption)
                                    .foregroundStyle(NV.inkTertiary)
                            }
                            .foregroundStyle(NV.ink)
                            .padding(.horizontal, NV.Space.m)
                            .padding(.vertical, 9)
                            .background(NV.sparkSoft)
                            .clipShape(RoundedRectangle(
                                cornerRadius: NV.Radius.control,
                                style: .continuous
                            ))
                        }
                    }
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Saved", subtitle: saved.isEmpty ? nil : "\(saved.count) items")
            if saved.isEmpty {
                NVEmptyState(
                    icon: "bookmark",
                    title: "Nothing saved yet",
                    message: "Tap the bookmark on anything you want to come back to."
                )
                .padding(.vertical, NV.Space.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: NV.Space.m) {
                        ForEach(saved) { item in
                            NavigationLink(value: item) {
                                RailCard(content: item, onOpen: {}).allowsHitTesting(false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var signOut: some View {
        NVButton(title: "Sign out", kind: .secondary) {
            Task { await session.signOut() }
        }
    }

    private func load() async {
        await session.loadSubjects()
        try? await session.loadMe()
        if let stage = session.profile?.stage, let grade = session.profile?.grade {
            gradeMap = try? await session.gradeCurriculum(stage: stage, grade: grade)
        }
        saved = (try? await session.api.authed(.get, "saved", as: [ContentDTO].self)) ?? []
        history = (try? await session.api.authed(
            .get, "me/history", query: ["days": "14"], as: [HistoryDayDTO].self
        )) ?? []
    }
}

/// One editor for the facts that drive both recommendations and the Passport.
///
/// It writes concrete course selections back to the profile. The Passport does
/// not keep a copy; its next load is derived from these same values.
struct LearningProfileEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var stage: String = "high"
    @State private var grade: String = "11"
    @State private var curriculum: String?
    @State private var gradeMap: GradeCurriculumDTO?
    @State private var selectedCourses: [String] = []
    @State private var courseNames: [String: String] = [:]
    @State private var focusSubjects: [String] = []
    @State private var focusGoals: [String: String] = [:]
    @State private var focusAreas: [String: [String]] = [:]
    @State private var loading = false
    @State private var busy = false
    @State private var error: APIError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.xl) {
                    schoolSection

                    if loading {
                        HStack(spacing: NV.Space.s) {
                            ProgressView().controlSize(.small)
                            Text("Loading course map…")
                                .font(NV.small).foregroundStyle(NV.inkTertiary)
                        }
                    } else if let gradeMap {
                        courseSection(gradeMap)
                        focusSection(gradeMap)
                        areaSection(gradeMap)
                    }

                    if let error {
                        NVErrorNote(message: error.message, retry: {
                            Task { await loadCurriculum() }
                        })
                    }
                }
                .padding(NV.Space.l)
            }
            .background(NV.page)
            .navigationTitle("My learning profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .task {
                hydrate()
                await loadCurriculum()
            }
        }
    }

    private var canSave: Bool {
        !selectedCourses.isEmpty
            && !focusSubjects.isEmpty
            && focusSubjects.allSatisfy { focusGoals[$0] != nil }
            && gradeMap != nil
            && !loading
            && !busy
    }

    private var schoolSection: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("SCHOOL & GRADE")
                .font(NV.caption).foregroundStyle(NV.inkTertiary)
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(Onb.stages) { option in
                    NVChip(text: option.label, selected: stage == option.slug) {
                        guard stage != option.slug else { return }
                        stage = option.slug
                        grade = Onb.grades(for: stage).first?.slug ?? ""
                        resetLearningSelections()
                        Task { await loadCurriculum() }
                    }
                }
            }
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(Onb.grades(for: stage)) { option in
                    NVChip(text: option.label, selected: grade == option.slug) {
                        guard grade != option.slug else { return }
                        grade = option.slug
                        resetLearningSelections()
                        Task { await loadCurriculum() }
                    }
                }
            }
            Text("CURRICULUM · OPTIONAL")
                .font(NV.caption).foregroundStyle(NV.inkTertiary)
                .padding(.top, NV.Space.s)
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(Onb.curricula) { option in
                    NVChip(text: option.label, selected: curriculum == option.slug) {
                        curriculum = curriculum == option.slug ? nil : option.slug
                    }
                }
            }
        }
    }

    private func courseSection(_ map: GradeCurriculumDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            NVSectionHeader(
                title: "Current courses",
                subtitle: "\(map.gradeLabel) · \(map.ageRange)"
            )
            Text("Pick the classes you take now. Add the exact local title when it differs.")
                .font(NV.small).foregroundStyle(NV.inkTertiary)
            ForEach(map.courses) { course in
                editorCourseCard(course)
            }
        }
    }

    private func focusSection(_ map: GradeCurriculumDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(
                title: "Focus subjects",
                subtitle: "Each one needs a goal"
            )
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(map.courses) { course in
                    NVChip(
                        text: course.subjectName,
                        icon: course.icon,
                        selected: focusSubjects.contains(course.subjectSlug)
                    ) {
                        if let index = focusSubjects.firstIndex(of: course.subjectSlug) {
                            focusSubjects.remove(at: index)
                            focusGoals[course.subjectSlug] = nil
                            pruneEditorAreas()
                        } else {
                            focusSubjects.append(course.subjectSlug)
                        }
                    }
                }
            }

            ForEach(focusSubjects, id: \.self) { subjectSlug in
                let course = map.courses.first { $0.subjectSlug == subjectSlug }
                focusGoalRow(
                    subjectSlug: subjectSlug,
                    subjectName: course?.subjectName ?? subjectSlug
                )
            }
        }
    }

    private func areaSection(_ map: GradeCurriculumDTO) -> some View {
        let subjects = editorAreaSubjects(map)
        return VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(
                title: "Inside those subjects",
                subtitle: "Biology is not one thing"
            )
            Text("Pick the chapters Novi should actually feed you.")
                .font(NV.small).foregroundStyle(NV.inkTertiary)
            ForEach(subjects, id: \.subjectSlug) { course in
                VStack(alignment: .leading, spacing: NV.Space.s) {
                    Text(course.subjectName.uppercased())
                        .font(NV.caption).foregroundStyle(NV.inkTertiary)
                    FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                        ForEach(Onb.areas(for: course.subjectSlug)) { option in
                            let selected = (focusAreas[course.subjectSlug] ?? [])
                                .contains(option.slug)
                            NVChip(text: option.label, selected: selected) {
                                toggleEditorArea(subject: course.subjectSlug, area: option.slug)
                            }
                        }
                    }
                }
            }
        }
    }

    private func editorCourseCard(_ course: CurriculumCourseDTO) -> some View {
        let selected = selectedCourses.contains(course.slug)
        return VStack(alignment: .leading, spacing: NV.Space.s) {
            Button {
                if let index = selectedCourses.firstIndex(of: course.slug) {
                    selectedCourses.remove(at: index)
                    courseNames[course.slug] = nil
                    pruneEditorAreas()
                } else {
                    selectedCourses.append(course.slug)
                }
            } label: {
                HStack(alignment: .top, spacing: NV.Space.m) {
                    Image(systemName: course.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? NV.spark : NV.inkTertiary)
                        .frame(width: 32, height: 32)
                        .background(selected ? NV.sparkSoft : NV.surfaceSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.subjectName)
                            .font(NV.caption).foregroundStyle(NV.inkTertiary)
                        Text(course.name)
                            .font(NV.smallStrong).foregroundStyle(NV.ink)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? NV.spark : NV.track)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected {
                TextField(
                    "Exact class name (optional)",
                    text: Binding(
                        get: { courseNames[course.slug] ?? "" },
                        set: { courseNames[course.slug] = $0 }
                    )
                )
                .font(NV.small)
                .padding(.horizontal, NV.Space.m)
                .frame(height: 40)
                .background(NV.surface)
                .clipShape(RoundedRectangle(cornerRadius: NV.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: NV.Radius.control)
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

    private func focusGoalRow(subjectSlug: String, subjectName: String) -> some View {
        let goal = focusGoals[subjectSlug]
        return Menu {
            ForEach(Onb.focusGoals) { option in
                Button {
                    focusGoals[subjectSlug] = option.slug
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
                    Text(subjectName)
                        .font(NV.smallStrong).foregroundStyle(NV.ink)
                    Text(Onb.focusGoalLabel(goal))
                        .font(NV.caption)
                        .foregroundStyle(goal == nil ? NV.spark : NV.inkTertiary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NV.inkTertiary)
            }
            .padding(NV.Space.m)
            .edgedSurface()
        }
    }

    private func editorAreaSubjects(_ map: GradeCurriculumDTO?) -> [CurriculumCourseDTO] {
        guard let map else { return [] }
        var seen = Set<String>()
        var out: [CurriculumCourseDTO] = []
        for slug in selectedCourses {
            guard let course = map.courses.first(where: { $0.slug == slug }) else { continue }
            if seen.insert(course.subjectSlug).inserted {
                out.append(course)
            }
        }
        for subject in focusSubjects where seen.insert(subject).inserted {
            if let course = map.courses.first(where: { $0.subjectSlug == subject }) {
                out.append(course)
            }
        }
        return out.filter { !Onb.areas(for: $0.subjectSlug).isEmpty }
    }

    private func toggleEditorArea(subject: String, area: String) {
        var current = focusAreas[subject] ?? []
        if let index = current.firstIndex(of: area) {
            current.remove(at: index)
        } else {
            current.append(area)
        }
        if current.isEmpty {
            focusAreas[subject] = nil
        } else {
            focusAreas[subject] = current
        }
    }

    private func pruneEditorAreas() {
        let keep = Set(editorAreaSubjects(gradeMap).map(\.subjectSlug))
        focusAreas = focusAreas.filter { keep.contains($0.key) }
    }

    private var submittedEditorAreas: [String: [String]] {
        Dictionary(uniqueKeysWithValues: editorAreaSubjects(gradeMap).compactMap { course in
            let picked = focusAreas[course.subjectSlug] ?? []
            return picked.isEmpty ? nil : (course.subjectSlug, picked)
        })
    }

    private func hydrate() {
        let profile = session.profile
        stage = profile?.stage ?? "high"
        grade = profile?.grade ?? Onb.grades(for: stage).first?.slug ?? "11"
        curriculum = profile?.curriculum
        selectedCourses = []
        courseNames = [:]
        for selection in profile?.currentCourses ?? []
        where !selectedCourses.contains(selection.courseSlug) {
            selectedCourses.append(selection.courseSlug)
            courseNames[selection.courseSlug] = selection.name
        }
        focusSubjects = []
        for subject in profile?.weakSubjects ?? []
        where !focusSubjects.contains(subject) {
            focusSubjects.append(subject)
        }
        focusGoals = profile?.focusGoals ?? [:]
        focusAreas = profile?.focusAreas ?? [:]
    }

    private func resetLearningSelections() {
        gradeMap = nil
        selectedCourses = []
        courseNames = [:]
        focusSubjects = []
        focusGoals = [:]
        focusAreas = [:]
        error = nil
    }

    private func loadCurriculum() async {
        let requestedStage = stage
        let requestedGrade = grade
        guard !requestedGrade.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let map: GradeCurriculumDTO = try await session.gradeCurriculum(
                stage: requestedStage, grade: requestedGrade
            )
            guard stage == requestedStage, grade == requestedGrade else { return }
            gradeMap = map
            let validCourses = Set(map.courses.map(\.slug))
            let validSubjects = Set(map.courses.map(\.subjectSlug))
            selectedCourses = selectedCourses.filter(validCourses.contains)
            courseNames = courseNames.filter { validCourses.contains($0.key) }
            focusSubjects = focusSubjects.filter(validSubjects.contains)
            focusGoals = focusGoals.filter { validSubjects.contains($0.key) }
            focusAreas = focusAreas.filter { validSubjects.contains($0.key) }
            error = nil
        } catch let apiError as APIError {
            gradeMap = nil
            error = apiError
        } catch {
            gradeMap = nil
            self.error = APIError.transport(error)
        }
    }

    private func save() {
        guard canSave else { return }
        busy = true
        error = nil
        Task {
            do {
                try await session.updateProfile(
                    LearningProfilePatchBody(
                        stage: stage,
                        grade: grade,
                        curriculum: curriculum,
                        currentCourses: selectedCourses.map { slug in
                            CurrentCourseSelectionDTO(
                                courseSlug: slug,
                                name: courseNames[slug, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        },
                        focusSubjectSlugs: focusSubjects,
                        focusGoals: focusGoals,
                        focusAreas: submittedEditorAreas
                    )
                )
                busy = false
                dismiss()
            } catch let apiError as APIError {
                error = apiError
                busy = false
            } catch {
                self.error = APIError.transport(error)
                busy = false
            }
        }
    }
}
