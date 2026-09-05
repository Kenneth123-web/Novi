import Foundation
import SwiftUI

/// A language the interface ships in.
///
/// The list is deliberately short: every entry is a language the whole UI is
/// translated into, not a language content can be in. `native` is the endonym,
/// shown in the picker so someone who does not read the current UI language
/// can still find their own.
struct AppLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    let native: String

    var id: String { code }

    /// The six UN languages, with Chinese split by script — Simplified and
    /// Traditional are separate Apple locales and need separate catalog entries.
    static let all: [AppLanguage] = [
        AppLanguage(code: "en", name: "English", native: "English"),
        AppLanguage(code: "ar", name: "Arabic", native: "العربية"),
        AppLanguage(code: "zh-Hans", name: "Chinese (Simplified)", native: "简体中文"),
        AppLanguage(code: "zh-Hant", name: "Chinese (Traditional)", native: "繁體中文"),
        AppLanguage(code: "fr", name: "French", native: "Français"),
        AppLanguage(code: "ru", name: "Russian", native: "Русский"),
        AppLanguage(code: "es", name: "Spanish", native: "Español"),
    ]

    static let fallbackCode = "en"

    /// Normalize an Apple locale id or a persisted code to one of the offered
    /// languages. Unsupported values fall back to English rather than leaving
    /// a dead picker value on screen.
    static func canonicalCode(_ raw: String?) -> String {
        let value = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !value.isEmpty else { return fallbackCode }

        let lower = value.lowercased()
        if lower.hasPrefix("zh-hant") || ["zh-tw", "zh-hk", "zh-mo"].contains(lower) {
            return "zh-Hant"
        }
        if lower.hasPrefix("zh-hans") || ["zh-cn", "zh-sg", "zh"].contains(lower) {
            return "zh-Hans"
        }

        let base = lower.split(separator: "-", maxSplits: 1).first.map(String.init) ?? lower
        return all.first(where: { $0.code == base })?.code ?? fallbackCode
    }

    /// Best match for the device language, so "System" resolves to the
    /// language the phone is already in when we ship it.
    static var deviceDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = canonicalCode(preferred)
        return all.first { $0.code == code } ?? all[0]
    }
}

/// In-app UI language.
///
/// The catalog keys ARE the English copy, and the app language is chosen
/// in-app (Settings → Language), not inherited from the iPhone. SwiftUI
/// `Text("…")` literals follow `environment(\.locale)`; strings held in
/// variables (enum labels, option rows) go through `String.localized`, which
/// looks up the SAME catalog with the chosen locale pinned — never the system
/// one, so a Chinese phone with the app set to English cannot leak 中文 into
/// one label while the rest reads English.
enum AppLocalization {
    /// The `AppLanguage.code` currently driving the UI. Static so computed
    /// labels (`"Home".localized`) resolve without every caller threading a
    /// locale through. `LanguageStore` is the only writer.
    static var code: String = AppLanguage.deviceDefault.code

    static var locale: Locale { Locale(identifier: localeIdentifier(for: code)) }

    /// Script-qualified Chinese codes have to stay whole — collapsing them to
    /// `zh` would pick the system default script and show 简体 to a 繁體 reader.
    static func localeIdentifier(for code: String) -> String {
        let canonical = AppLanguage.canonicalCode(code)
        switch canonical {
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        default: return canonical
        }
    }

    /// SwiftUI does not infer layout direction from a custom in-app locale
    /// environment. Keep Arabic right-to-left even when the device itself is
    /// set to a left-to-right language.
    static func layoutDirection(for code: String) -> LayoutDirection {
        AppLanguage.canonicalCode(code) == "ar" ? .rightToLeft : .leftToRight
    }
}

extension String {
    /// Look this English source string up in the current app language.
    ///
    /// The catalog keys ARE the English UI copy, so a missing translation
    /// falls back to this string rather than to a raw key like `home.tab`.
    var localized: String {
        String(localized: String.LocalizationValue(self), locale: AppLocalization.locale)
    }

    func localized(_ arguments: CVarArg...) -> String {
        String(format: localized, locale: AppLocalization.locale, arguments: arguments)
    }
}

/// The user's language choice, persisted. "system" means follow the iPhone;
/// anything else is an `AppLanguage.code` and wins over the device language.
///
/// Published so the root can re-apply `environment(\.locale)` and re-render
/// the whole tree on a switch — a language the user just picked that only
/// shows after a restart would read as broken.
final class LanguageStore: ObservableObject {
    static let selectionKey = "appLanguage"

    @Published var selection: String {
        didSet {
            UserDefaults.standard.set(selection, forKey: Self.selectionKey)
            AppLocalization.code = resolvedCode
            Self.applyDirection(for: resolvedCode)
        }
    }

    var resolvedCode: String {
        selection == "system" ? AppLanguage.deviceDefault.code : AppLanguage.canonicalCode(selection)
    }

    init() {
        // `-demoLang ar` launch argument wins, so every language can be
        // screenshotted on a simulator whose system language stays put. The
        // argument lives in the volatile argument domain and is never written
        // back, so it cannot stick past the run that asked for it.
        let demo = UserDefaults.standard.string(forKey: "demoLang")
        let saved = UserDefaults.standard.string(forKey: Self.selectionKey)
        let initial = demo ?? saved ?? "system"
        selection = initial
        AppLocalization.code = initial == "system" ? AppLanguage.deviceDefault.code : AppLanguage.canonicalCode(initial)
        Self.applyDirection(for: AppLocalization.code)
    }

    /// The SwiftUI `\.layoutDirection` environment is ignored at the window
    /// root on iOS 17 — the scene's trait collection wins there — so Arabic
    /// also forces the direction at the UIKit level. Both say the same thing;
    /// neither alone covers every OS version.
    static func applyDirection(for code: String) {
        let attribute: UISemanticContentAttribute =
            AppLanguage.canonicalCode(code) == "ar" ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attribute
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.semanticContentAttribute = attribute
            }
        }
    }
}
