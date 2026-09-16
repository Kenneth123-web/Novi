import SwiftUI

/// Who is signed in, and which shell the app should be showing.
///
/// One enum rather than a pair of booleans: "signed in but not onboarded" is a
/// real state with its own screen, and two independent flags make it possible
/// to render a personalised feed for somebody who has no profile to
/// personalise it from.
@MainActor
final class AppSession: ObservableObject {

    enum Phase: Equatable {
        /// Before the stored token has been checked. Distinct from `signedOut`
        /// so a returning user does not see the sign-in screen flash past on
        /// every cold launch.
        case launching
        case signedOut
        case onboarding(UserDTO)
        case ready(UserDTO)
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var profile: ProfileDTO?
    @Published private(set) var subjects: [SubjectDTO] = []

    /// Set when the AI gateway is down, so the Ask screen can say what is
    /// wrong once rather than every view guessing.
    @Published var aiNotice: String?

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    var user: UserDTO? {
        switch phase {
        case .onboarding(let u), .ready(let u): return u
        case .launching, .signedOut: return nil
        }
    }

    // MARK: Launch

    func start() async {
        await api.setAuthenticationLostHandler { [weak self] in
            Task { @MainActor in
                self?.phase = .signedOut
                self?.profile = nil
            }
        }
        // Local-network permission + picking Wi-Fi/USB/Bonjour happen here,
        // not on the first skip tap — that tap used to sit behind a 150s
        // timeout and then say the server was unreachable.
        await api.prepareNetwork()

        if Demo.resetSession { await api.signOutLocally() }

        if Demo.skipLogin {
            try? await skipAsDeveloper()
            if case .launching = phase { phase = .signedOut }
            return
        }

        if let credentials = Demo.credentials {
            // A development shortcut. Failures are silent on purpose: a demo
            // account that no longer exists should land on the normal sign-in
            // screen, not on an error the real app would never show.
            try? await signIn(email: credentials.email, password: credentials.password)
            if case .launching = phase { phase = .signedOut }
            return
        }

        guard await api.hasSession() else {
            phase = .signedOut
            return
        }
        do {
            try await loadMe()
        } catch {
            // Being offline at launch is not a sign-out, but there is nothing
            // to show without a profile either, so the sign-in screen is where
            // this lands — with the stored token left alone.
            phase = .signedOut
        }
    }

    // MARK: Auth

    func signUp(email: String, username: String, password: String, displayName: String)
        async throws
    {
        let response: AuthResponseDTO = try await api.send(
            .post, "auth/register",
            body: RegisterBody(
                email: email, username: username, password: password, displayName: displayName
            )
        )
        await api.store(response.tokens)
        apply(user: response.user)
    }

    func prepareNetwork() async {
        await api.prepareNetwork()
    }

    func signIn(email: String, password: String) async throws {
        let response: AuthResponseDTO = try await api.send(
            .post, "auth/login", body: LoginBody(email: email, password: password)
        )
        await api.store(response.tokens)
        await enter(response.user)
    }

    /// `POST /auth/dev-skip` — a real session for the reserved developer
    /// account, not a fake phase override. Production APIs 404 this route.
    ///
    /// Skip is a login, not a completed profile. If grade / weak subjects
    /// are missing, this still lands on the questionnaire.
    func skipAsDeveloper() async throws {
        let response: AuthResponseDTO = try await api.send(
            .post, "auth/dev-skip", body: DevSkipBody()
        )
        await api.store(response.tokens)
        await enter(response.user)
    }

    func signOut() async {
        // Revoke server-side first. A local-only sign-out leaves a long-lived
        // refresh token alive on a device the user may be handing over.
        if let refresh = await api.currentRefreshToken() {
            _ = try? await api.send(
                .post, "auth/logout", body: RefreshBody(refreshToken: refresh),
                as: EmptyResponse.self
            )
        }
        await api.signOutLocally()
        phase = .signedOut
        profile = nil
    }

    // MARK: Profile

    func loadMe() async throws {
        let me: MeDTO = try await api.authed(.get, "me")
        profile = me.profile
        apply(user: me.user)
    }

    func loadSubjects() async {
        guard subjects.isEmpty else { return }
        subjects = (try? await api.send(.get, "subjects", as: [SubjectDTO].self)) ?? []
    }

    func completeOnboarding(_ body: OnboardingBody) async throws {
        let me: MeDTO = try await api.authed(.post, "onboarding", body: body)
        profile = me.profile
        apply(user: me.user)
    }

    func updateProfile(_ patch: ProfilePatchBody) async throws {
        let me: MeDTO = try await api.authed(.patch, "me", body: patch)
        profile = me.profile
        apply(user: me.user)
    }

    /// Fire-and-forget behaviour reporting.
    ///
    /// Deliberately not awaited by callers and deliberately silent on failure:
    /// a dropped analytics write must never interrupt what the learner is
    /// doing, and a visible error for one would be worse than the missing row.
    func track(
        _ kind: String,
        contentID: UUID? = nil,
        conceptID: UUID? = nil,
        dwellSeconds: Int = 0
    ) {
        Task {
            _ = try? await api.authed(
                .post, "interactions",
                body: InteractionBody(
                    kind: kind,
                    contentId: contentID?.uuidString,
                    conceptId: conceptID?.uuidString,
                    dwellSeconds: dwellSeconds
                ),
                as: EmptyResponse.self
            )
        }
    }

    private func enter(_ user: UserDTO) async {
        do {
            try await loadMe()
        } catch {
            apply(user: user)
        }
    }

    /// A signed-in user without grade + stuck-subjects is not ready. The
    /// feed would rank against an empty profile and look personalised
    /// when it is not.
    private func profileIsPersonalised(_ profile: ProfileDTO?) -> Bool {
        guard let profile else { return false }
        let grade = (profile.grade ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !grade.isEmpty && !profile.weakSubjects.isEmpty && !profile.subjectOrder.isEmpty
    }

    private func apply(user: UserDTO) {
        // The questionnaire is about the profile, not the onboarded_at
        // timestamp. Skip-login used to clear that timestamp on every tap,
        // which would otherwise trap a completed profile on the welcome page.
        if profileIsPersonalised(profile) {
            phase = .ready(user)
        } else {
            phase = .onboarding(user)
        }
    }
}
