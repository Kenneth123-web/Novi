import SwiftUI

/// Sign in and sign up on one screen with a mode toggle, rather than two
/// screens behind a welcome page. A returning user opening the app should be
/// one tap from a keyboard, not three.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                fields.padding(.top, NV.Space.xl)

                // Field-level messages sit on their fields; this is for
                // anything the server could not attribute to one.
                if let error, error.fieldErrors.isEmpty {
                    NVErrorNote(message: error.message, retry: error.isRetryable ? submit : nil)
                        .padding(.top, NV.Space.l)
                }

                NVButton(
                    title: mode == .signIn ? "Sign in" : "Create account",
                    loading: busy,
                    enabled: canSubmit,
                    action: submit
                )
                .padding(.top, NV.Space.xl)

                toggleRow.padding(.top, NV.Space.l)
                Spacer(minLength: NV.Space.section)
            }
            .padding(.horizontal, NV.Space.xl)
            .padding(.top, NV.Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NV.surface)
        // Clearing on a mode flip stops "that email is already taken" sitting
        // above a sign-in form where it makes no sense.
        .onChange(of: mode) { _, _ in error = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("Novi")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(NV.accent)
            Text(mode == .signIn ? "Welcome back." : "Welcome to your learning world.")
                .font(NV.h1)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("A feed that teaches you something, an AI tutor that knows what you're studying, and a passport that remembers all of it.")
                .font(NV.small)
                .foregroundStyle(NV.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(spacing: NV.Space.l) {
            NVField(
                title: "Email", text: $email, placeholder: "you@example.com",
                error: error?.message(for: "email"),
                contentType: .emailAddress, keyboard: .emailAddress
            )
            if mode == .signUp {
                NVField(
                    title: "Username", text: $username, placeholder: "3–40 characters",
                    error: error?.message(for: "username"), contentType: .username
                )
                NVField(
                    title: "Display name", text: $displayName,
                    placeholder: "What people see (optional)", contentType: .name
                )
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
        }
    }

    private var toggleRow: some View {
        HStack(spacing: NV.Space.xs) {
            Text(mode == .signIn ? "New here?" : "Already have an account?")
                .font(NV.small)
                .foregroundStyle(NV.inkFaint)
            Button(mode == .signIn ? "Create one" : "Sign in") {
                withAnimation(.easeOut(duration: 0.15)) {
                    mode = mode == .signIn ? .signUp : .signIn
                }
            }
            .font(NV.small.weight(.semibold))
            .foregroundStyle(NV.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 8 else { return false }
        return mode == .signIn || username.count >= 3
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                if mode == .signIn {
                    try await session.signIn(email: email, password: password)
                } else {
                    try await session.signUp(
                        email: email, username: username, password: password,
                        displayName: displayName.isEmpty ? username : displayName
                    )
                }
            } catch let apiError as APIError {
                error = apiError
            } catch {
                self.error = APIError.transport(error)
            }
            busy = false
        }
    }
}
