import AppKit
import AuthenticationServices
import Foundation
import TokenVault

/// Mở authorize URL bằng ASWebAuthenticationSession (trình duyệt hệ thống, RFC 8252).
/// Loopback nhận callback rồi 302 về `app.vdaily.keyloft://oauth-complete` — session
/// chờ đúng scheme đó rồi trả về. Nếu loopback xong trước (task bị hủy) → cancel session.
@MainActor
final class WebAuthBrowserSession: NSObject, BrowserSession, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var pending: CheckedContinuation<Void, any Error>?

    nonisolated func present(_ url: URL, callbackScheme: String) async throws {
        try await presentOnMain(url, callbackScheme: callbackScheme)
    }

    private func presentOnMain(_ url: URL, callbackScheme: String) async throws {
        let handler: (URL?, Error?) -> Void = { callbackURL, error in
            Task { @MainActor in
                self.finish(callbackURL: callbackURL, error: error)
            }
        }
        let session: ASWebAuthenticationSession
        if #available(macOS 14.4, *) {
            session = ASWebAuthenticationSession(
                url: url, callback: .customScheme(callbackScheme), completionHandler: handler)
        } else {
            session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme, completionHandler: handler)
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        self.session = session

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.pending = continuation
                if !session.start() {
                    // Không thể mở — trả continuation ngay (finish đã nil pending).
                    self.finish(callbackURL: nil, error: BrowserSessionError.failed("không mở được trình duyệt"))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel()
            }
        }
    }

    private func finish(callbackURL: URL?, error: Error?) {
        guard let continuation = pending else { return }
        pending = nil
        session = nil

        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            {
                continuation.resume(throwing: BrowserSessionError.userCancelled)
                return
            }
            continuation.resume(throwing: BrowserSessionError.failed(nsError.localizedDescription))
            return
        }
        guard callbackURL != nil else {
            continuation.resume(throwing: BrowserSessionError.failed("không có callback URL"))
            return
        }
        continuation.resume()
    }

    /// Loopback nhận callback trước khi browser đóng → hủy session (SPEC-005 Risks).
    private func cancel() {
        session?.cancel()
        guard let continuation = pending else { return }
        pending = nil
        session = nil
        continuation.resume(throwing: BrowserSessionError.userCancelled)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
        -> ASPresentationAnchor
    {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? ASPresentationAnchor()
        }
    }
}
