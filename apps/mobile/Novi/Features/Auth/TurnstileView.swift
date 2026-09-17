import SwiftUI
import WebKit

/// Cloudflare Turnstile widget. The sitekey is public; the secret stays on
/// the siteverify Worker. Tokens are posted back through a script handler
/// and then sent to `POST /auth/register` or `/auth/login` for server-side
/// verification — this view never calls siteverify itself.
struct TurnstileView: UIViewRepresentable {
    let siteKey: String
    let widgetURL: URL?
    var action: String = "turnstile-spin-v1"
    let onToken: (String) -> Void
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken, onReset: onReset) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "turnstile")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.load(in: webView, siteKey: siteKey, widgetURL: widgetURL, action: action)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.siteKey != siteKey || context.coordinator.action != action {
            context.coordinator.load(in: webView, siteKey: siteKey, widgetURL: widgetURL, action: action)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstile")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onToken: (String) -> Void
        let onReset: () -> Void
        var siteKey = ""
        var action = ""

        init(onToken: @escaping (String) -> Void, onReset: @escaping () -> Void) {
            self.onToken = onToken
            self.onReset = onReset
        }

        func load(in webView: WKWebView, siteKey: String, widgetURL: URL?, action: String) {
            self.siteKey = siteKey
            self.action = action
            if let widgetURL, var parts = URLComponents(url: widgetURL, resolvingAgainstBaseURL: false) {
                var query = parts.queryItems ?? []
                query.removeAll { $0.name == "sitekey" || $0.name == "action" }
                query.append(URLQueryItem(name: "sitekey", value: siteKey))
                query.append(URLQueryItem(name: "action", value: action))
                parts.queryItems = query
                if let url = parts.url {
                    webView.load(URLRequest(url: url))
                    return
                }
            }
            let html = Self.html(siteKey: siteKey, action: action)
            webView.loadHTMLString(
                html,
                baseURL: URL(string: "https://novi-console.rememberly-kenneth.workers.dev")
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }
            let event = body["event"] as? String ?? ""
            if event == "success", let token = body["token"] as? String, !token.isEmpty {
                onToken(token)
            } else {
                onReset()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onReset()
        }

        private static func html(siteKey: String, action: String) -> String {
            let key = siteKey
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let act = action
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            return """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
              <style>
                html, body { margin: 0; padding: 0; background: transparent; }
                .wrap { display: flex; justify-content: center; }
              </style>
              <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
            </head>
            <body>
              <div class="wrap">
                <div class="cf-turnstile"
                     data-sitekey="\(key)"
                     data-action="\(act)"
                     data-theme="light"
                     data-size="flexible"
                     data-callback="onOk"
                     data-error-callback="onErr"
                     data-expired-callback="onExp"></div>
              </div>
              <script>
                function post(p) {
                  try { window.webkit.messageHandlers.turnstile.postMessage(p); } catch (e) {}
                }
                function onOk(t) { post({event: 'success', token: t}); }
                function onErr() { post({event: 'error'}); }
                function onExp() { post({event: 'expired'}); }
              </script>
            </body>
            </html>
            """
        }
    }
}
