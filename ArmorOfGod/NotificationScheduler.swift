import Foundation
import UserNotifications

/**
 * Schedules the aggressive reminders for Armor of God events:
 *  - DAY BEFORE the event (24 hours prior)
 *  - DAY OF, ONE HOUR BEFORE
 * Apple's limits (honest): notifications appear on the lock screen with an alarm
 * sound, vibration, and Acknowledge / Snooze buttons, and persist until addressed.
 * iOS does not allow an app to forcibly take over the screen, and the physical
 * mute switch silences notification sounds. Keep the mute switch off for
 * can't-miss events. (A "Critical Alerts" entitlement from Apple can bypass the
 * mute switch — see README.)
 */
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { ok, _ in
                    DispatchQueue.main.async { completion(ok) }
                }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            default:
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    /// Fetch events from the web app and (re)schedule all alarms.
    func syncAndSchedule() {
        guard AlarmSyncClient.shared.hasAccount else { return }
        AlarmSyncClient.shared.fetchEvents { events in
            guard let events = events, !events.isEmpty else { return }
            self.schedule(events: events)
        }
    }

    func schedule(events: [PlannedEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let sorted = events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var scheduled = 0
        for event in sorted {
            guard let start = event.nextOccurrence(after: now) else { continue }
            for (kind, offset, text) in [("day_before", -86400.0, "Your event is TOMORROW"),
                                        ("one_hour", -3600.0, "Your event starts in ONE HOUR")] {
                if scheduled >= 28 { return } // iOS caps at 64 pending notifications
                let fireDate = start.addingTimeInterval(offset)
                if fireDate <= now { continue }
                add(event: event, kind: kind, bodyText: text, date: fireDate)
                scheduled += 1
            }
        }
    }

    private func add(event: PlannedEvent, kind: String, bodyText: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 " + event.title
        content.body = bodyText + (event.notes.isEmpty ? "" : " · " + event.notes)
        content.categoryIdentifier = "AOG_EVENT"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["id": event.id, "title": event.title, "notes": event.notes, "kind": kind]
        content.sound = alarmSound()

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "aog_" + event.id + "_" + kind,
                                             content: content, trigger: trigger)
        center.add(request)
    }

    /// Same event, 10 minutes later (Snooze button).
    func snooze(eventId: String, title: String, notes: String, kind: String) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 " + title
        content.body = "Snoozed event reminder"
        content.categoryIdentifier = "AOG_EVENT"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["id": eventId, "title": title, "notes": notes, "kind": kind]
        content.sound = alarmSound()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: "aog_snooze_" + eventId,
                                             content: content, trigger: trigger)
        center.add(request)
    }

    /// The settings-screen test: a real notification through the whole chain.
    func testAlarm() {
        let content = UNMutableNotificationContent()
        content.title = "🔔 Test alarm"
        content.body = "This is what a real event alert looks like."
        content.categoryIdentifier = "AOG_EVENT"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["id": "test", "title": "Test alarm", "notes": "", "kind": "test"]
        content.sound = alarmSound()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
        let request = UNNotificationRequest(identifier: "aog_test", content: content, trigger: trigger)
        center.add(request)
    }

    /// Uses the bundled AlarmSound.wav if present, else the system default.
    private func alarmSound() -> UNNotificationSound {
        if Bundle.main.url(forResource: "AlarmSound", withExtension: "wav") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("AlarmSound.wav"))
        }
        return .default
    }
}
