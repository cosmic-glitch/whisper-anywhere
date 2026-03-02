import AppKit
import Foundation
import WebKit

@MainActor
protocol TurnstileTokenProviding: AnyObject {
    var isConfigured: Bool { get }
    func fetchToken() async throws -> String
}

enum TurnstileTokenError: LocalizedError {
    case siteKeyMissing
    case alreadyRunning
    case timedOut
    case cancelled
    case challengeFailed(String)

    var errorDescription: String? {
        switch self {
        case .siteKeyMissing:
            return "Turnstile site key is not configured."
        case .alreadyRunning:
            return "A security check is already in progress."
        case .timedOut:
            return "Security check timed out."
        case .cancelled:
            return "Security check was cancelled."
        case .challengeFailed(let message):
            return "Security check failed: \(message)"
        }
    }
}

@MainActor
final class TurnstileTokenService: NSObject, TurnstileTokenProviding {
    private let siteKey: String
    private let timeoutNanoseconds: UInt64

    private var challengeWindow: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(siteKey: String, timeoutNanoseconds: UInt64 = 90_000_000_000) {
        self.siteKey = siteKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    var isConfigured: Bool {
        !siteKey.isEmpty
    }

    func fetchToken() async throws -> String {
        guard isConfigured else {
            throw TurnstileTokenError.siteKeyMissing
        }

        guard continuation == nil else {
            throw TurnstileTokenError.alreadyRunning
        }

        let userContentController = WKUserContentController()
        userContentController.add(self, name: "turnstileToken")
        userContentController.add(self, name: "turnstileError")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 220), configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Security Check"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()

        challengeWindow = window
        self.webView = webView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let html = Self.challengeHTML(siteKey: siteKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://whisperanywhere.app"))

        let timeoutNanoseconds = self.timeoutNanoseconds
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard let self else {
                return
            }
            self.finish(with: .failure(TurnstileTokenError.timedOut))
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.continuation = continuation
        }
    }

    private func finish(with result: Result<String, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        if let webView {
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstileToken")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstileError")
        }

        challengeWindow?.orderOut(nil)
        challengeWindow = nil
        webView = nil

        switch result {
        case .success(let token):
            continuation.resume(returning: token)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private static func challengeHTML(siteKey: String) -> String {
        """
        <!doctype html>
        <html lang=\"en\">
          <head>
            <meta charset=\"utf-8\" />
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
            <style>
              body {
                margin: 0;
                font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif;
                background: rgba(13, 20, 38, 0.95);
                color: #e6eefb;
                display: flex;
                align-items: center;
                justify-content: center;
                height: 100vh;
              }
              .wrap {
                width: 360px;
                text-align: center;
              }
              .label {
                font-size: 13px;
                opacity: 0.82;
                margin-bottom: 12px;
              }
              #cf-turnstile {
                display: inline-block;
              }
            </style>
            <script src=\"https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit\" async defer></script>
          </head>
          <body>
            <div class=\"wrap\">
              <div class=\"label\">Verifying request…</div>
              <div id=\"cf-turnstile\"></div>
            </div>
            <script>
              function post(name, payload) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
                  window.webkit.messageHandlers[name].postMessage(payload);
                }
              }

              function renderTurnstile() {
                if (!window.turnstile) {
                  setTimeout(renderTurnstile, 50);
                  return;
                }

                window.turnstile.render('#cf-turnstile', {
                  sitekey: '\(siteKey)',
                  callback: function(token) {
                    post('turnstileToken', token || '');
                  },
                  'error-callback': function(code) {
                    post('turnstileError', code || 'unknown_error');
                  },
                  'expired-callback': function() {
                    post('turnstileError', 'token_expired');
                  },
                  'timeout-callback': function() {
                    post('turnstileError', 'challenge_timeout');
                  }
                });
              }

              renderTurnstile();
            </script>
          </body>
        </html>
        """
    }
}

@MainActor
extension TurnstileTokenService: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            switch message.name {
            case "turnstileToken":
                let token = String(describing: message.body).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else {
                    finish(with: .failure(TurnstileTokenError.challengeFailed("empty token")))
                    return
                }
                finish(with: .success(token))
            case "turnstileError":
                let details = String(describing: message.body)
                finish(with: .failure(TurnstileTokenError.challengeFailed(details)))
            default:
                break
            }
        }
    }
}

@MainActor
extension TurnstileTokenService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(TurnstileTokenError.challengeFailed(error.localizedDescription)))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(TurnstileTokenError.challengeFailed(error.localizedDescription)))
        }
    }
}

@MainActor
extension TurnstileTokenService: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        finish(with: .failure(TurnstileTokenError.cancelled))
    }
}
