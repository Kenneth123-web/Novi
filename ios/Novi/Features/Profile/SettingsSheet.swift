import SwiftUI

/// Settings. Today that is exactly one thing — the interface language — so
/// the sheet skips the menu level and lists the languages directly. Each
/// language names itself (the endonym), because someone looking for their
/// language is precisely the person who cannot read the current one.
struct SettingsSheet: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(NV.inkSoft)
                Spacer()
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NV.ink)
                Spacer()
                Text("Cancel").font(.system(size: 15)).opacity(0)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .hairline()

            HStack {
                Text("Language")
                    .font(.system(size: 13))
                    .foregroundStyle(NV.inkGhost)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                // "System" names what it resolves to, so the choice is not a
                // leap of faith.
                row(id: "system", title: "System".localized, subtitle: AppLanguage.deviceDefault.native)
                ForEach(AppLanguage.all) { lang in
                    row(id: lang.code, title: lang.native, subtitle: lang.name == lang.native ? nil : lang.name)
                }
            }

            Spacer()
        }
        .background(NV.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func row(id: String, title: String, subtitle: String?) -> some View {
        Button {
            language.selection = id
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(NV.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(NV.inkGhost)
                }
                Spacer()
                if language.selection == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NV.red)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
