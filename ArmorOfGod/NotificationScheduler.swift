import Foundation
import UserNotifications

/// A scheduled alarm fire, persisted so a MISSED alarm can still demand the
/// swipe-right acknowledgment the next time the app is opened — however late.
struct ExpectedFire: Codable {
    let id: String        // event id or "test"
    let title: String
    let notes: String
    let kind: String      // day_before | one_hour | snooze | test
    let fireISO: String   // ISO8601 fire time

    var fireDate: Date? { ISO8601DateFormatter().date(from: fireISO) }
}

/**
 * Schedules the aggressive Armor of God reminders:
 *  - DAY BEFORE the event (24 hours prior)
 *  - DAY OF, ONE HOUR BEFORE
 *
 * Fire behavior (as Clock-like as iOS allows for an app):
 *  - The notification rings with a long alarm sound. A repeat chain re-fires it
 *    4 and 8 minutes later if it was missed, buzzing the phone again.
 *  - Tapping the notification (or opening the app later) shows a FULL-SCREEN
 *    alarm with a looping ringtone that plays even on the silent switch, plus
 *    repeated vibration. The only way out is SLIDING RIGHT to acknowledge.
 *  - Every expected fire is persisted; if it is never acknowledged, the app
 *    demands the swipe on every open until it happens.
 */
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    private let firesKey = "aog_expected_fires"
    private let ackKey = "aog_acked_fires"

    // MARK: Authorization

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { ok, _ in
                    DispatchQueue.main.async { completion(ok) }
                }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            default:
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    // MARK: Sync + schedule

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
        var fires = [ExpectedFire]()
        let sorted = events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var alarmsScheduled = 0
        for event in sorted {
            guard let start = event.nextOccurrence(after: now) else { continue }
            for (kind, offset, text) in [("day_before", -86400.0, "Your event is TOMORROW"),
                                         ("one_hour", -3600.0, "Your event starts in ONE HOUR")] {
                // 20 alarms * 3 notifications (fire + 2 repeats) = 60, under the 64 cap.
                if alarmsScheduled >= 20 { break }
                let fireDate = start.addingTimeInterval(offset)
                if fireDate <= now { continue }
                add(event: event, kind: kind, bodyText: text, date: fireDate)
                fires.append(ExpectedFire(id: event.id, title: event.title, notes: event.notes,
                                          kind: kind, fireISO: iso.string(from: fireDate)))
                alarmsScheduled += 1
            }
        }
        saveFires(fires)
    }

    private func add(event: PlannedEvent, kind: String, bodyText: String, date: Date) {
        // Main fire + repeat chain: if the first alert is slept through, the
        // phone rings again 4 minutes and 8 minutes later.
        addNotification(id: event.id, title: event.title, notes: event.notes, kind: kind,
                        bodyText: bodyText, date: date, suffix: "")
        addNotification(id: event.id, title: event.title, notes: event.notes, kind: kind,
                        bodyText: "MISSED ALARM — ringing again", date: date.addingTimeInterval(4 * 60),
                        suffix: "_r1")
        addNotification(id: event.id, title: event.title, notes: event.notes, kind: kind,
                        bodyText: "STILL UNACKNOWLEDGED — acknowledge this!",
                        date: date.addingTimeInterval(8 * 60), suffix: "_r2")
    }

    private func addNotification(id: String, title: String, notes: String, kind: String,
                                 bodyText: String, date: Date, suffix: String) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 " + title
        content.body = bodyText + (notes.isEmpty ? "" : " · " + notes)
        content.categoryIdentifier = "AOG_EVENT"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["id": id, "title": title, "notes": notes, "kind": kind,
                            "fireISO": iso.string(from: date)]
        content.sound = alarmSound()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "aog_" + id + "_" + kind + suffix,
                                            content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: Snooze / test

    /// Same event, 10 minutes later (Snooze action on the notification).
    func snooze(eventId: String, title: String, notes: String, kind: String) {
        let date = Date().addingTimeInterval(10 * 60)
        addNotification(id: eventId, title: title, notes: notes, kind: "snooze",
                        bodyText: "Snoozed reminder — acknowledge when it rings", date: date, suffix: "")
        let fire = ExpectedFire(id: eventId, title: title, notes: notes, kind: "snooze",
                                 fireISO: iso.string(from: date))
        var fires = loadFires().filter { !($0.id == eventId && $0.kind == "snooze") }
        fires.append(fire)
        saveFires(fires)
    }

    /// The settings-screen test: a real notification through the whole chain.
    /// Recorded as an expected fire too — miss it and the app still demands
    /// the swipe next time it opens.
    func testAlarm() {
        let date = Date().addingTimeInterval(15)
        addNotification(id: "test", title: "Test alarm", notes: "", kind: "test",
                        bodyText: "This is what a real event alert feels like.", date: date, suffix: "")
        var fires = loadFires().filter { $0.id != "test" }
        fires.append(ExpectedFire(id: "test", title: "Test alarm", notes: "", kind: "test",
                                  fireISO: iso.string(from: date)))
        saveFires(fires)
    }

    // MARK: Missed-alarm persistence

    /// Alarms that have fired (or were missed) and are NOT yet acknowledged.
    /// Older than 7 days counts as expired so the list can never wedge the app.
    func unacknowledgedAlarms(now: Date = Date()) -> [PendingAlarm] {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let acked = loadAcked()
        return loadFires().compactMap { fire -> PendingAlarm? in
            guard let date = fire.fireDate, date <= now, date > cutoff else { return nil }
            let key = ackKey(fire)
            guard !acked.contains(key) else { return nil }
            return PendingAlarm(id: fire.id, title: fire.title, notes: fire.notes,
                                kind: fire.kind, firedAt: date)
        }
    }

    /// Called ONLY by the full-screen alarm's slide-right.
    func markAcknowledged(_ alarm: PendingAlarm) {
        var acked = loadAcked()
        acked.insert(ackKey(ExpectedFire(id: alarm.id, title: alarm.title, notes: alarm.notes,
                                         kind: alarm.kind, fireISO: iso.string(from: alarm.firedAt))))
        saveAcked(acked)
        // Stop the repeat chain for this alarm.
        center.removePendingNotificationRequests(withIdentifiers:
            ["aog_\(alarm.id)_\(alarm.kind)", "aog_\(alarm.id)_\(alarm.kind)_r1",
             "aog_\(alarm.id)_\(alarm.kind)_r2"])
        // Report to the web app so the dashboard updates ASAP (unless it's a test).
        if alarm.id != "test" {
            AlarmSyncClient.shared.reportAck(eventId: alarm.id, title: alarm.title, kind: alarm.kind)
        }
    }

    // MARK: Storage helpers

    private var iso: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private func ackKey(_ fire: ExpectedFire) -> String {
        fire.id + "|" + fire.kind + "|" + fire.fireISO
    }

    private func loadFires() -> [ExpectedFire] {
        guard let data = UserDefaults.standard.data(forKey: firesKey),
              let fires = try? JSONDecoder().decode([ExpectedFire].self, from: data) else { return [] }
        return fires
    }

    private func saveFires(_ fires: [ExpectedFire]) {
        // Merge in snooze/test fires that are still in the future.
        let existing = loadFires()
        let now = Date()
        let keep = existing.filter { fire in
            guard (fire.fireDate ?? now) > now else { return false }
            if fire.id == "test" {
                // Only the newest test alarm survives; pressing "Test" twice
                // must not stack two swipe-screens.
                return !fires.contains(where: { $0.id == "test" })
            }
            return fire.kind == "snooze" &&
                !fires.contains(where: { $0.id == fire.id && $0.kind == fire.kind })
        }
        let merged = (fires + keep).filter { ($0.fireDate ?? now) > now.addingTimeInterval(-7 * 86400) }
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: firesKey)
        }
    }

    private func loadAcked() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ackKey) ?? [])
    }

    private func saveAcked(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set).suffix(200), forKey: ackKey)
    }

    /// Uses the bundled 30-second AlarmSound.wav if present, else the system default.
    private func alarmSound() -> UNNotificationSound {
        if Bundle.main.url(forResource: "AlarmSound", withExtension: "wav") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("AlarmSound.wav"))
        }
        return .default
    }
}
