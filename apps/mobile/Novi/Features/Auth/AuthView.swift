import SwiftUI

/// Sign in and sign up on one screen with a mode toggle, rather than two
/// screens behind a welcome page. A returning user opening the app should be
/// one tap from a keyboard, not three.
///
/// The aurora carries over from the opening — quieter, because a form has to
/// be read — so the app does not change character between the second screen
/// and the third. The mark shrinks to a header glyph rather than disappearing.
struct AuthView: View {
    @EnvironmentObject private var session: AppSession

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signUp

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""

    @State private var busy = false
    @State private var error: APIError?
    @State private var captcha: CaptchaConfigDTO?
    @State private var turnstileToken = ""
    @State private var captchaEpoch = 0
    @FocusState private var focused: Field?

    private enum Field { case email, username, displayName, password }

    var body: some View {
        ZStack {
            // Much quieter than the opening. At 0.30 the wash ran the full
            // height and the input fills sank into it; a form has to out-read
            // its background, so the colour is kept to a suggestion.
            AuroraBackdrop(strength: 0.16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    fields.padding(.top, NV.Space.xl)

                    // Field-level messages sit on their fields; this is for
                    // anything the server could not attribute to one.
                    if let error,
                       error.fieldErrors.isEmpty || error.message(for: "turnstile_token") != nil {
                        NVErrorNote(
                            message: error.message(for: "turnstile_token") ?? error.message,
                            retry: error.isRetryable ? submit : nil
                        )
                        .padding(.top, NV.Space.l)
                    }

                    captchaBox
                        .padding(.top, NV.Space.l)

                    NVButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        loading: busy,
                        enabled: canSubmit,
                        action: submit
                    )
                    .padding(.top, NV.Space.xl)

                    #if DEBUG
                    NVButton(
                        title: "Skip as developer",
                        kind: .quiet,
                        loading: busy,
                        action: skipDeveloper
                    )
                    .padding(.top, NV.Space.s)
                    #endif

                    toggleRow.padding(.top, NV.Space.l)
                    Spacer(minLength: NV.Space.section)
                }
                .padding(.horizontal, NV.pageMargin)
                .padding(.top, NV.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Clearing on a mode flip stops "that email is already taken" sitting
        // above a sign-in form where it makes no sense.
        .onChange(of: mode) { _, _ in
            error = nil
            resetCaptcha()
        }
        .task {
            await session.prepareNetwork()
            await loadCaptcha()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            BrandMark(progress: BrandMark.filled, size: 60)

            VStack(alignment: .leading, spacing: NV.Space.s) {
                Text(mode == .signIn ? "Welcome back." : "Welcome to your\nlearning world.")
                    .displayStyle(10)
                    .foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(mode == .signIn
                     ? "Pick up where you left off."
                     : "A feed that teaches you something, and a passport that keeps what you learn.")
                    .font(NV.body)
                    .foregroundStyle(NV.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fields: some View {
        VStack(spacing: NV.Space.l) {
            NVField(
                title: "Email", text: $email, placeholder: "you@example.com",
                error: error?.message(for: "email"),
                contentType: .emailAddress, keyboard: .emailAddress
            )
            .focused($focused, equals: .email)

            if mode == .signUp {
                NVField(
                    title: "Username", text: $username, placeholder: "3–40 characters",
                    error: error?.message(for: "username"), contentType: .username
                )
                .focused($focused, equals: .username)

                NVField(
                    title: "Display name", text: $displayName,
                    placeholder: "What people see (optional)", contentType: .name
                )
                .focused($focused, equals: .displayName)
            }

            NVField(
                title: "Password", text: $password,
                placeholder: mode == .signUp ? "8+ characters, letters and digits" : "",
                secure: true, error: error?.message(for: "password"),
                // `.password` on sign-up asks the keychain to save the wrong
                // thing; `.newPassword` is what offers a strong suggestion.
                contentType: mode == .signUp ? .newPassword : .password,
                submitLabel: .go, onSubmit: submit
            )
            .focused($focused, equals: .password)
        }
    }

    private var toggleRow: some View {
        HStack(spacing: NV.Space.xs) {
            Text(mode == .signIn ? "New here?" : "Already have an account?")
                .font(NV.small)
                .foregroundStyle(NV.inkTertiary)
            Button(mode == .signIn ? "Create one" : "Sign in") {
                withAnimation(.easeOut(duration: 0.18)) {
                    mode = mode == .signIn ? .signUp : .signIn
                }
            }
            .font(NV.smallStrong)
            .foregroundStyle(NV.spark)
        }
        .frame(maxWidth: .infinity)
    }

    private var captchaBox: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            if let captcha, captcha.enabled, !captcha.sitekey.isEmpty {
                TurnstileView(
                    siteKey: captcha.sitekey,
                    widgetURL: URL(string: captcha.widgetUrl),
                    action: captcha.action.isEmpty ? "turnstile-spin-v1" : captcha.action,
                    onToken: { turnstileToken = $0 },
                    onReset: { turnstileToken = "" }
                )
                .id(captchaEpoch)
                .frame(height: 72)
            } else if captcha == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            } else {
                Text("Couldn't load the CAPTCHA. Check the connection and try again.")
                    .font(NV.small)
                    .foregroundStyle(NV.inkSecondary)
                Button("Retry") { Task { await loadCaptcha() } }
                    .font(NV.smallStrong)
                    .foregroundStyle(NV.spark)
            }
        }
    }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 8, !turnstileToken.isEmpty else { return false }
        return mode == .signIn || username.count >= 3
    }

    private func loadCaptcha() async {
        do {
            captcha = try await session.loadCaptchaConfig()
        } catch {
            captcha = CaptchaConfigDTO(
                provider: "turnstile", enabled: false, sitekey: "",
                action: "turnstile-spin-v1", widgetUrl: ""
            )
        }
        resetCaptcha()
    }

    private func resetCaptcha() {
        turnstileToken = ""
        captchaEpoch += 1
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        busy = true
        error = nil
        focused = nil
        Task {
            do {
                if mode == .signIn {
                    try await session.signIn(
                        email: email, password: password, turnstileToken: turnstileToken
                    )
                } else {
                    try await session.signUp(
                        email: email, username: username, password: password,
                        displayName: displayName.isEmpty ? username : displayName,
                        turnstileToken: turnstileToken
                    )
                }
            } catch let apiError as APIError {
                error = apiError
                resetCaptcha()
            } catch {
                self.error = APIError.transport(error)
                resetCaptcha()
            }
            busy = false
        }
    }

    #if DEBUG
    private func skipDeveloper() {
        guard !busy else { return }
        busy = true
        error = nil
        focused = nil
        Task {
            do {
                try await session.skipAsDeveloper()
            } catch let apiError as APIError {
                error = apiError
            } catch {
                self.error = APIError.transport(error)
            }
            busy = false
        }
    }
    #endif
}
