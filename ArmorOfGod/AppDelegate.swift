import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let ack = UNNotificationAction(identifier: "ACK", title: "I acknowledge this event", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Snooze 10 minutes", options: [])
        let category = UNNotificationCategory(identifier: "AOG_EVENT", actions: [ack, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: WebViewController())
        window?.makeKeyAndVisible()
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        NotificationScheduler.shared.syncAndSchedule()
    }

    // Show event alerts even when the app is open, with sound.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // Acknowledge / Snooze buttons.
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
        } else if !id.isEmpty && id != "test" {
            AlarmSyncClient.shared.reportAck(eventId: id, title: title, kind: kind)
        }
        completionHandler()
    }
}
