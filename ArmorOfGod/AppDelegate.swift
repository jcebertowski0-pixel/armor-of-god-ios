import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    static let ackReloadNotification = Notification.Name("aog_ack_completed")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AogDiag.installCrashHandlers()
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        AogDiag.log("=== LAUNCH v\(v) build \(b) ios \(UIDevice.current.systemVersion) ===")
        if UserDefaults.standard.bool(forKey: "aog_ack_in_progress") {
            // The previous run died in the middle of an acknowledgment.
            AogDiag.log("PREVIOUS RUN DIED DURING ACK - see breadcrumbs above")
            UserDefaults.standard.set(false, forKey: "aog_ack_in_progress")
        }

        UNUserNotificationCenter.current().delegate = self
        // No "acknowledge" button on the notification: the ONLY way to acknowledge
        // is the full-screen alarm's slide-right, like stopping a Clock alarm.
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Snooze 10 minutes", options: [])
        let category = UNNotificationCategory(identifier: "AOG_EVENT", actions: [snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = RootNavController(rootViewController: WebViewController())
        window?.makeKeyAndVisible()

        // Cold launch with a missed alarm: demand the swipe right away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.presentMissedAlarms() }
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        NotificationScheduler.shared.syncAndSchedule()
        // Missed an alarm while away? Acknowledge it now — however late.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.presentMissedAlarms() }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        presentMissedAlarms()
    }

    // MARK: Full-screen alarm queue

    private var alarmQueue: [PendingAlarm] = []
    private var alarmOnScreen = false

    /// Shows a Clock-style full-screen alarm for every unacknowledged (missed)
    /// alarm, one at a time, each demanding a slide-right.
    func presentMissedAlarms() {
        if !alarmOnScreen {
            for p in NotificationScheduler.shared.unacknowledgedAlarms()
            where !alarmQueue.contains(where: { $0.id == p.id && $0.kind == p.kind && $0.firedAt == p.firedAt }) {
                alarmQueue.append(p)
            }
        }
        presentNextAlarm()
    }

    private var currentAlarm: PendingAlarm?
    private weak var alarmVC: AlarmAlertViewController?

    private func presentNextAlarm() {
        guard !alarmOnScreen, let root = window?.rootViewController, let window = window else { return }
        // Skip queue entries that already got their swipe: acking one alarm of
        // a calendar event acks all of its alarms — an acknowledged fire must
        // never take over the screen a second time.
        while !alarmQueue.isEmpty {
            let next = alarmQueue.removeFirst()
            if NotificationScheduler.shared.isAcknowledged(next) { continue }
            // The alarm is a plain overlay on the window, NOT a modal. There is
            // no presentation/dismissal transition anywhere in this flow any
            // more: nothing to race, nothing that can wedge UIKit mid-transition,
            // and the only exit is removing one view.
            root.dismiss(animated: false)   // clears any web-layer sheet; no-op if none
            alarmOnScreen = true
            currentAlarm = next
            AogDiag.log("PRESENT alarm id=\(next.id) kind=\(next.kind) title=\(next.title)")
            let vc = AlarmAlertViewController(event: next) { acknowledged in
                AogDiag.log("ACK callback -> markAcknowledged")
                NotificationScheduler.shared.markAcknowledged(acknowledged)
                AogDiag.log("ACK callback done")
                // Refresh the web app so the acknowledgment shows ASAP. Posted
                // async so it can never run inside the ack's own stack.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: AppDelegate.ackReloadNotification, object: nil)
                }
            }
            root.addChild(vc)
            vc.view.frame = window.bounds
            vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            vc.didMove(toParent: root)
            window.addSubview(vc.view)
            alarmVC = vc
            (root as? RootNavController)?.statusBarOwner = vc
            root.setNeedsStatusBarAppearanceUpdate()
            AogDiag.log("PRESENT done")
            return
        }
    }

    /// "Test alarm NOW" on the Phone Alarms screen: full-screen alarm immediately.
    func presentTestAlarmNow() {
        let alarm = PendingAlarm(id: "test", title: "Test alarm", notes: "", kind: "test", firedAt: Date())
        alarmQueue.removeAll { $0.id == "test" }
        alarmQueue.insert(alarm, at: 0)
        presentNextAlarm()
    }

    /// Called by AlarmAlertViewController after its slide-right. Pure view
    /// teardown: no dismissal animation to wait on, so the next alarm (if any)
    /// can never race a UIKit transition.
    func removeAlarmScreen(_ vc: AlarmAlertViewController) {
        AogDiag.log("SCREEN remove")
        vc.stopNoise()
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        if alarmVC === vc { alarmVC = nil }
        (window?.rootViewController as? RootNavController)?.statusBarOwner = nil
        window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        alarmOnScreen = false
        currentAlarm = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.presentNextAlarm()
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    // Ring banners + sound even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == "AOG_EVENT" {
            // App in the foreground? Take the whole screen instead of a quiet banner.
            completionHandler([])
            presentNotificationAlarm(notification)
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    // Tapping the notification (or its Snooze action).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["id"] as? String ?? ""
        let title = info["title"] as? String ?? ""
        let notes = info["notes"] as? String ?? ""
        let kind = info["kind"] as? String ?? ""
        if response.actionIdentifier == "SNOOZE" {
            NotificationScheduler.shared.snooze(eventId: id, title: title, notes: notes, kind: kind)
            completionHandler()
        } else {
            // Tap = full-screen alarm; the swipe-right is the only way out.
            presentNotificationAlarm(response.notification)
            completionHandler()
        }
    }

    private func presentNotificationAlarm(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        let id = info["id"] as? String ?? ""
        let title = info["title"] as? String ?? ""
        let notes = info["notes"] as? String ?? ""
        let kind = info["kind"] as? String ?? "one_hour"
        let fireISO = info["fireISO"] as? String ?? ""
        let fireDate = ISO8601DateFormatter().date(from: fireISO) ?? Date()
        let alarm = PendingAlarm(id: id, title: title, notes: notes, kind: kind, firedAt: fireDate)
        AogDiag.log("NOTIFICATION alarm id=\(id) kind=\(kind)")
        alarmQueue.removeAll { $0.id == alarm.id && $0.kind == alarm.kind && $0.firedAt == alarm.firedAt }
        alarmQueue.insert(alarm, at: 0)
        presentNextAlarm()
    }
}

// MARK: - Diagnostics

/// Tiny append-only breadcrumb log. Every step of the alarm/ack path writes one
/// line and flushes it straight to disk, so when the app dies the file shows the
/// exact step it died on. Read it in the app: bell button -> "Diagnostics".
enum AogDiag {

    private static let queue = DispatchQueue(label: "aog.diag")
    private static var logURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("aog-diagnostics.log")
    }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        queue.sync {
            let url = logURL
            // Plain, atomic file I/O: no FileHandle availability games, and the
            // line is on disk before this call returns, so a crash one
            // instruction later still leaves the breadcrumb behind.
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            var all = existing + line
            var lines = all.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 900 {
                lines = Array(lines.suffix(700))
                all = lines.joined(separator: "\n") + "\n"
            }
            try? all.write(to: url, atomically: true, encoding: .utf8)
        }
        NSLog("AOG %@", message)
    }

    static func tail(_ lines: Int = 400) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return "No diagnostics yet. Run an alarm and acknowledge it."
        }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        let slice = all.suffix(lines)
        return "=== last \(slice.count) lines ===\n" + slice.joined(separator: "\n")
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: logURL) }
    }

    /// Objective-C exceptions only. Signal handlers are deliberately NOT
    /// installed: they would replace Apple's own crash report (the .ips file),
    /// which is the ground truth we want. Breadcrumbs cover the rest.
    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            AogDiag.log("UNCAUGHT EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "no reason")")
            for frame in exception.callStackSymbols.prefix(25) {
                AogDiag.log("  \(frame)")
            }
        }
    }
}
