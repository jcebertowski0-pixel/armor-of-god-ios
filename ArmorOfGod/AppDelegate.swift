import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    static let ackReloadNotification = Notification.Name("aog_ack_completed")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // No "acknowledge" button on the notification: the ONLY way to acknowledge
        // is the full-screen alarm's slide-right, like stopping a Clock alarm.
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Snooze 10 minutes", options: [])
        let category = UNNotificationCategory(identifier: "AOG_EVENT", actions: [snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: WebViewController())
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
        for p in NotificationScheduler.shared.unacknowledgedAlarms()
        where !alarmQueue.contains(where: { $0.id == p.id && $0.kind == p.kind && $0.firedAt == p.firedAt })
            && !(alarmOnScreen && currentAlarm == p) {
            alarmQueue.append(p)
        }
        presentNextAlarm()
    }

    private var currentAlarm: PendingAlarm?

    private func presentNextAlarm() {
        guard !alarmOnScreen, let root = window?.rootViewController else { return }
        // Skip queue entries that already got their swipe: acking one alarm of
        // a calendar event acks all of its alarms — an acknowledged fire must
        // never take over the screen a second time.
        while !alarmQueue.isEmpty {
            let next = alarmQueue.removeFirst()
            if NotificationScheduler.shared.isAcknowledged(next) { continue }
            // Dismiss anything on top (webview modals, action sheets) so the alarm
            // truly takes over the screen.
            root.dismiss(animated: false)
            alarmOnScreen = true
            currentAlarm = next
            let vc = AlarmAlertViewController(event: next) { acknowledged in
                NotificationScheduler.shared.markAcknowledged(acknowledged)
                // Refresh the web app immediately so the acknowledgment shows ASAP.
                NotificationCenter.default.post(name: AppDelegate.ackReloadNotification, object: nil)
            }
            root.present(vc, animated: true)
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

    /// Called by AlarmAlertViewController after its slide-right and dismissal.
    func alarmScreenDidFinish() {
        alarmOnScreen = false
        currentAlarm = nil
        presentNextAlarm()
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
        alarmQueue.removeAll { $0.id == alarm.id && $0.kind == alarm.kind && $0.firedAt == alarm.firedAt }
        alarmQueue.insert(alarm, at: 0)
        presentNextAlarm()
    }
}
