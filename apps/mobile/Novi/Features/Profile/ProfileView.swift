import SwiftUI

/// Profile: who you are, what you saved, what you've been doing, and the one
/// setting that matters — the interests the feed is built from.
struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @State private var saved: [ContentDTO] = []
    @State private var history: [HistoryDayDTO] = []
    @State private var editingInterests = false
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
            .sheet(isPresented: $editingInterests) { InterestEditor() }
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
                title: "Customise my feed",
                subtitle: "What you pick here is what you see",
                action: ("Edit", { editingInterests = true })
            )
            if let profile = session.profile, !profile.subjectOrder.isEmpty {
                FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                    ForEach(profile.subjectOrder, id: \.self) { slug in
                        let name = session.subjects.first { $0.slug == slug }?.name ?? slug
                        let weight = profile.subjectInterests[slug] ?? 0
                        HStack(spacing: 5) {
                            Text(name).font(NV.small.weight(.medium))
                            // The live interest weight. Showing the number the
                            // ranker actually uses is the difference between a
                            // setting and a black box.
                            Text("\(Int(weight * 100))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NV.spark)
                        }
                        .foregroundStyle(NV.ink)
                        .padding(.horizontal, NV.Space.m)
                        .padding(.vertical, 9)
                        .cardSurface(NV.Radius.pill)
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
        saved = (try? await session.api.authed(.get, "saved", as: [ContentDTO].self)) ?? []
        history = (try? await session.api.authed(
            .get, "me/history", query: ["days": "14"], as: [HistoryDayDTO].self
        )) ?? []
    }
}

/// Re-picking subjects. Existing weights survive: a subject the learner has
/// actually engaged with should not be reset to its questionnaire default just
/// because they opened this sheet.
private struct InterestEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.m) {
                    Text("Tap order sets priority. The first subject leads your feed.")
                        .font(NV.small).foregroundStyle(NV.inkTertiary)
                    FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                        ForEach(session.subjects) { subject in
                            let rank = selected.firstIndex(of: subject.slug)
                            NVChip(
                                text: rank == nil ? subject.name : "\(rank! + 1). \(subject.name)",
                                selected: rank != nil
                            ) {
                                if let rank { selected.remove(at: rank) }
                                else { selected.append(subject.slug) }
                            }
                        }
                    }
                }
                .padding(NV.Space.l)
            }
            .background(NV.page)
            .navigationTitle("My interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(selected.isEmpty || busy)
                        .fontWeight(.semibold)
                }
            }
            .task { selected = session.profile?.subjectOrder ?? [] }
        }
    }

    private func save() {
        busy = true
        Task {
            try? await session.updateProfile(ProfilePatchBody(subjectSlugs: selected))
            busy = false
            dismiss()
        }
    }
}
