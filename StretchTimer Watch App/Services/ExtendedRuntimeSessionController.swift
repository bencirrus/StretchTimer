import Foundation
import WatchKit

@MainActor
final class ExtendedRuntimeSessionController: NSObject {
    private var session: WKExtendedRuntimeSession?
    private(set) var isRunning = false
    private var isApproved = true

    func startIfActive() {
        #if targetEnvironment(simulator)
        // Simulator does not approve extended runtime sessions.
        return
        #else
        guard isApproved else { return }
        guard WKExtension.shared().applicationState == .active else { return }
        if let session, session.state == .running || session.state == .scheduled {
            return
        }

        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        session = newSession
        newSession.start()
        #endif
    }

    func stop() {
        session?.invalidate()
        session = nil
        isRunning = false
    }
}

extension ExtendedRuntimeSessionController: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.isRunning = true
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Best-effort only; the system decides expiration timing.
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            _ = reason
            if let error = error as NSError?,
               error.domain == "com.apple.CarouselServices.SessionErrorDomain",
               error.code == 8 {
                self.isApproved = false
            }
            self.isRunning = false
            self.session = nil
        }
    }
}
