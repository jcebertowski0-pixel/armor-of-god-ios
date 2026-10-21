import Foundation
import UserNotifications

/// A scheduled alarm fire, persisted so a MISSED alarm can still demand the
/// swipe-right acknowledgment the next time the app is opened — however late.
struct ExpectedFire: Codable {
    let id: String        // event id, manual alarm id, or "test"
    let title: String
    let notes: String
    let kind: String      // day_before | one_hour | snooze | test | manual
    let fireISO: String   // ISO8601 fire time

    var fireDate: Date? { ISO8601DateFormatter().date(from: fireISO) }
}

/// An alarm the owner set directly on the phone (no web-app account needed).
struct ManualAlarm: Codable, Equatable {
    let id: String
    let title: String
    let hour: Int
    let minute: Int
    let daily: Bool
    /// For one-time alarms set on a specific day: the exact fire date/time.
    let dateISO: String?
}

/**
 * The alarm engine. Two sources of alarms:
 *  - MANUAL alarms set right on the phone (the main flow — no sign-in needed)
 *  - WEB-APP calendar events (optional sign-in): day-before + one-hour-before
 *
 * Fire behavior (as Clock-like as iOS allows for an app):
 *  - The notification rings with the selected alarm sound. A repeat chain
 *    re-fires it 4 and 8 minutes later if it was missed.
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
    private let manualKey = "aog_manual_alarms"

    static let ringtones = ["radar", "siren", "buzzer", "bell"]
    static let styles = ["clock", "dark", "red"]
    /// Attachable lead times for calendar events, in minutes before the event.
    static let leadOptions: [(minutes: Int, label: String)] = [
        (15, "15 min"), (30, "30 min"), (60, "1 hr"), (120, "2 hrs"), (180, "3 hrs"), (1440, "1 day")
    ]

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

    /// Re-arms everything: manual alarms (always) + web-app events (if signed in).
    func syncAndSchedule() {
        AlarmSyncClient.shared.fetchEvents { events in
            self.reschedule(events: events ?? [])
        }
    }

    func reschedule(events: [PlannedEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()
        var fires = [ExpectedFire]()
        var alarmsScheduled = 0

        // Manual alarms first — the owner set these by hand.
        for manual in loadManual() {
            guard alarmsScheduled < 20 else { break }
            let title = manual.title.isEmpty ? "Alarm" : manual.title
            if manual.daily {
                // A repeating trigger fires every day on its own, even if the
                // app is never opened again. No +4/+8 chain for these.
                addRepeatingNotification(id: manual.id, title: title, hour: manual.hour, minute: manual.minute)
                if let fireDate = nextOccurrence(hour: manual.hour, minute: manual.minute, after: now) {
                    fires.append(ExpectedFire(id: manual.id, title: title, notes: "",
                                              kind: "manual", fireISO: iso.string(from: fireDate)))
                }
            } else {
                // One-time: exact date+time if given, else next matching time.
                var fireDate: Date?
                if let isoDate = manual.dateISO, let d = ISO8601DateFormatter().date(from: isoDate) {
                    fireDate = d > now ? d : nil
                } else {
                    fireDate = nextOccurrence(hour: manual.hour, minute: manual.minute, after: now)
                }
                if let fd = fireDate {
                    addNotification(id: manual.id, title: title, notes: "", kind: "manual",
                                    bodyText: "Time to acknowledge this", date: fd, suffix: "")
                    fires.append(ExpectedFire(id: manual.id, title: title, notes: "",
                                              kind: "manual", fireISO: iso.string(from: fd)))
                }
            }
            alarmsScheduled += 1
        }

        let sorted = events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        for event in sorted {
            guard let start = event.nextOccurrence(after: now) else { continue }
            // The lead times the owner attached to THIS event.
            for m in eventOffsets(id: event.id).sorted() {
                if alarmsScheduled >= 20 { break }
                let fireDate = start.addingTimeInterval(-Double(m) * 60)
                if fireDate <= now { continue }
                addNotification(id: event.id, title: event.title, notes: event.notes,
                                kind: "lead_\(m)", bodyText: leadBody(m), date: fireDate, suffix: "")
                fires.append(ExpectedFire(id: event.id, title: event.title, notes: event.notes,
                                          kind: "lead_\(m)", fireISO: iso.string(from: fireDate)))
                alarmsScheduled += 1
            }
        }
        saveFires(fires)
    }

    /// Notification body text for a lead time.
    private func leadBody(_ minutes: Int) -> String {
        if minutes >= 1440 {
            return minutes / 1440 == 1 ? "Your event is TOMORROW" : "Your event is in \(minutes / 1440) days"
        }
        if minutes >= 60 {
            return minutes == 60 ? "Your event starts in ONE HOUR"
                                  : "Your event starts in \(minutes / 60) HOURS"
        }
        return "Your event starts in \(minutes) MINUTES"
    }

    /// The alarm lead times (minutes before the event) attached to one calendar
    /// event. Default keeps the classic pair: 1 hour + 1 day before.
    func eventOffsets(id: String) -> Set<Int> {
        if let arr = UserDefaults.standard.array(forKey: "aog_offsets_\(id)") as? [Int] {
            return Set(arr)
        }
        return [60, 1440]
    }

    func setEventOffsets(id: String, offsets: Set<Int>) {
        UserDefaults.standard.set(Array(offsets.sorted()), forKey: "aog_offsets_\(id)")
        syncAndSchedule()
    }

    /// Clear custom offsets back to the default pair.
    func resetEventOffsets(id: String) {
        UserDefaults.standard.removeObject(forKey: "aog_offsets_\(id)")
        syncAndSchedule()
    }

    /// A daily alarm: one repeating notification, fires at hour:minute forever.
    private func addRepeatingNotification(id: String, title: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 " + title
        content.body = "Time to acknowledge this"
        content.categoryIdentifier = "AOG_EVENT"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["id": id, "title": title, "notes": "", "kind": "manual", "fireISO": ""]
        content.sound = alarmSound()
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "aog_" + id + "_manual",
                                         content: content, trigger: trigger))
    }

    /// Next time this hour:minute occurs at or after `now` (today or tomorrow).
    private func nextOccurrence(hour: Int, minute: Int, after now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        if let next = cal.nextDate(after: now.addingTimeInterval(-1), matching: comps,
                                    matchingPolicy: .nextTime) {
            return next >= now ? next : cal.date(byAdding: .day, value: 1, to: next)
        }
        return nil
    }

    private func addNotification(id: String, title: String, notes: String, kind: String,
                                 bodyText: String, date: Date, suffix: String) {
        // Main fire + repeat chain: if the first alert is slept through, the
        // phone rings again 4 minutes and 8 minutes later.
        let triple: [(String, Date, String)] = [
            (suffix, date, bodyText),
            ("\(suffix)_r1", date.addingTimeInterval(4 * 60), "MISSED ALARM — ringing again"),
            ("\(suffix)_r2", date.addingTimeInterval(8 * 60), "STILL UNACKNOWLEDGED — acknowledge this!")
        ]
        for (sfx, when, body) in triple {
            guard when > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "🔔 " + title
            content.body = body + (notes.isEmpty ? "" : " · " + notes)
            content.categoryIdentifier = "AOG_EVENT"
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["id": id, "title": title, "notes": notes, "kind": kind,
                                 "fireISO": iso.string(from: date)]
            content.sound = alarmSound()
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "aog_" + id + "_" + kind + sfx,
                                                content: content, trigger: trigger)
            center.add(request)
        }
    }

    // MARK: Manual alarms (the simple flow: set + test, no account)

    func loadManual() -> [ManualAlarm] {
        guard let data = UserDefaults.standard.data(forKey: manualKey),
              let alarms = try? JSONDecoder().decode([ManualAlarm].self, from: data) else { return [] }
        return alarms
    }

    @discardableResult
    func addManual(title: String, hour: Int, minute: Int, daily: Bool, dateISO: String? = nil) -> ManualAlarm {
        let alarm = ManualAlarm(id: UUID().uuidString,
                                title: title.isEmpty ? "Alarm" : title,
                                hour: hour, minute: minute, daily: daily, dateISO: daily ? nil : dateISO)
        var all = loadManual()
        all.append(alarm)
        saveManual(all)
        syncAndSchedule()
        return alarm
    }

    func removeManual(id: String) {
        saveManual(loadManual().filter { $0.id != id })
        syncAndSchedule()
    }

    private func saveManual(_ alarms: [ManualAlarm]) {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: manualKey)
        }
    }

    // MARK: Snooze / test

    /// Same alarm, 10 minutes later (Snooze action on the notification).
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

    /// The full notification chain test: rings in 15 seconds. Recorded as an
    /// expected fire too — miss it and the app still demands the swipe next
    /// time it opens.
    func testAlarm() {
        let date = Date().addingTimeInterval(15)
        addNotification(id: "test", title: "Test alarm", notes: "", kind: "test",
                        bodyText: "This is what a real alarm feels like.", date: date, suffix: "")
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
            guard !acked.contains(ackKey(fire)) else { return nil }
            return PendingAlarm(id: fire.id, title: fire.title, notes: fire.notes,
                                kind: fire.kind, firedAt: date)
        }
    }

    /// Called ONLY by the full-screen alarm's slide-right.
    func markAcknowledged(_ alarm: PendingAlarm) {
        var acked = loadAcked()
        // Ack this exact fire plus any same-alarm fires that already passed
        // (a repeating daily alarm's notification carries its first fire date).
        acked.insert(ackKey(ExpectedFire(id: alarm.id, title: alarm.title, notes: alarm.notes,
                                         kind: alarm.kind, fireISO: iso.string(from: alarm.firedAt))))
        for fire in loadFires() where fire.id == alarm.id && fire.kind == alarm.kind {
            if let d = fire.fireDate, d <= alarm.firedAt.addingTimeInterval(600) {
                acked.insert(ackKey(fire))
            }
        }
        saveAcked(acked)
        // Stop the repeat chain — but never kill a daily alarm's repeating trigger.
        let isDailyManual = alarm.kind == "manual" && loadManual().contains(where: { $0.id == alarm.id && $0.daily })
        if !isDailyManual {
            center.removePendingNotificationRequests(withIdentifiers:
                ["aog_\(alarm.id)_\(alarm.kind)", "aog_\(alarm.id)_\(alarm.kind)_r1",
                 "aog_\(alarm.id)_\(alarm.kind)_r2"])
        }
        if alarm.kind == "manual" {
            // A one-time manual alarm is done after its one fire.
            if let m = loadManual().first(where: { $0.id == alarm.id }), !m.daily {
                saveManual(loadManual().filter { $0.id != alarm.id })
            }
        }
        // Web-app alarms report to the dashboard; manual/test alarms stay local.
        if alarm.kind.hasPrefix("lead_") || alarm.kind == "day_before" || alarm.kind == "one_hour"
            || alarm.kind == "snooze" {
            AlarmSyncClient.shared.reportAck(eventId: alarm.id, title: alarm.title, kind: alarm.kind)
        }
    }

    // MARK: Ringtone + style selection

    var ringtone: String {
        let r = UserDefaults.standard.string(forKey: "aog_ringtone") ?? "radar"
        return NotificationScheduler.ringtones.contains(r) ? r : "radar"
    }

    func setRingtone(_ name: String) {
        UserDefaults.standard.set(name, forKey: "aog_ringtone")
        syncAndSchedule() // re-arm notifications with the new sound
    }

    var style: String {
        let s = UserDefaults.standard.string(forKey: "aog_alarm_style") ?? "clock"
        return NotificationScheduler.styles.contains(s) ? s : "clock"
    }

    func setStyle(_ name: String) {
        UserDefaults.standard.set(name, forKey: "aog_alarm_style")
    }

    /// File name of the selected ringtone (bundled in the app).
    static func soundFile(for ringtone: String) -> String {
        switch ringtone {
        case "siren": return "AlarmSiren.wav"
        case "buzzer": return "AlarmBuzzer.wav"
        case "bell": return "AlarmBell.wav"
        default: return "AlarmSound.wav"
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
        // Preserve everything that still matters from the previous list:
        //  - past fires (last 7 days) that are NOT acknowledged — they still
        //    demand a swipe, so a resync must never erase a missed alarm
        //  - future snooze/test fires not already in the fresh list
        let existing = loadFires()
        let now = Date()
        let acked = loadAcked()
        let keep = existing.filter { fire in
            let d = fire.fireDate ?? now
            if d <= now {
                // Past + unacknowledged = still waiting for its swipe.
                return d > now.addingTimeInterval(-7 * 86400) && !acked.contains(ackKey(fire))
            }
            if fire.id == "test" {
                return !fires.contains(where: { $0.id == "test" })
            }
            return fire.kind == "snooze" &&
                !fires.contains(where: { $0.id == fire.id && $0.kind == fire.kind })
        }
        var merged = fires + keep
        // De-dupe by the ack key, keeping the fresh copies.
        var seen = Set<String>()
        merged = merged.filter { seen.insert($0.id + "|" + $0.kind + "|" + $0.fireISO).inserted }
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

    /// The selected ringtone as a notification sound.
    private func alarmSound() -> UNNotificationSound {
        let file = NotificationScheduler.soundFile(for: ringtone)
        if Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                          withExtension: "wav") != nil {
            return UNNotificationSound(named: UNNotificationSoundName(file))
        }
        return .default
    }
}
