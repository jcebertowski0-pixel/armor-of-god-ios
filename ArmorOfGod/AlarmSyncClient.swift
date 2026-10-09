import Foundation

/// One calendar event synced from the Armor of God web app.
struct PlannedEvent: Codable {
    let id: String
    let title: String
    let notes: String
    let event_start: String
    let repeat_daily: Bool

    private var startDate: Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: event_start) { return d }
        return ISO8601DateFormatter().date(from: event_start)
    }

    /// The next time this event occurs, at or after `now`.
    func nextOccurrence(after now: Date) -> Date? {
        guard let start = startDate else { return nil }
        if !repeat_daily { return start >= now ? start : nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.hour, .minute], from: start)
        if let today = cal.date(byAdding: comps, to: cal.startOfDay(for: now)), today >= now {
            return today
        }
        return cal.date(byAdding: comps, to: cal.startOfDay(for: now).addingTimeInterval(86400))
    }
}

private struct EventsResponse: Codable { let events: [PlannedEvent] }

/**
 * Syncs calendar events from the Armor of God web app and reports acknowledgments.
 *
 * HONEST LIMITS: the account email and password are kept in UserDefaults for
 * automatic re-login (personal/family device trade-off). Only event titles, notes,
 * times, and acknowledgment records ever leave the phone.
 */
final class AlarmSyncClient {
    static let shared = AlarmSyncClient()
    private let base = URL(string: "https://divine-armor-path.base44.app")!
    private let appId = "69b073d713d45657aef116c5"

    var email: String? { UserDefaults.standard.string(forKey: "aog_email") }
    var hasAccount: Bool { (email ?? "").isEmpty == false }
    var lastSync: Date? { UserDefaults.standard.object(forKey: "aog_last_sync") as? Date }

    /// Blocking network on a background queue; completion on main. nil error = success.
    func login(email: String, password: String, completion: @escaping (String?) -> Void) {
        post(path: "auth/login", token: nil, body: ["email": email, "password": password]) { data, status in
            let error: String?
            if status == 200, let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = obj["access_token"] as? String, !token.isEmpty {
                UserDefaults.standard.set(email, forKey: "aog_email")
                UserDefaults.standard.set(password, forKey: "aog_password")
                UserDefaults.standard.set(token, forKey: "aog_token")
                error = nil
            } else if status == 400 || status == 401 {
                error = "Invalid email or password"
            } else {
                error = "Network error — check the connection"
            }
            DispatchQueue.main.async { completion(error) }
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: "aog_email")
        UserDefaults.standard.removeObject(forKey: "aog_password")
        UserDefaults.standard.removeObject(forKey: "aog_token")
    }

    /// Fetches upcoming events; automatically re-logins once if the token expired.
    func fetchEvents(completion: @escaping ([PlannedEvent]?) -> Void) {
        guard hasAccount else { DispatchQueue.main.async { completion(nil) }; return }
        if let token = UserDefaults.standard.string(forKey: "aog_token"), !token.isEmpty {
            fetchEvents(token: token, allowRetry: true, completion: completion)
        } else {
            relogin { token in
                if let token = token {
                    self.fetchEvents(token: token, allowRetry: false, completion: completion)
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        }
    }

    private func fetchEvents(token: String, allowRetry: Bool,
                             completion: @escaping ([PlannedEvent]?) -> Void) {
        post(path: "functions/listCalendarEvents", token: token, body: [:]) { data, status in
            if status == 200, let data = data,
               let events = (try? JSONDecoder().decode(EventsResponse.self, from: data))?.events {
                UserDefaults.standard.set(Date(), forKey: "aog_last_sync")
                DispatchQueue.main.async { completion(events) }
                return
            }
            if allowRetry {
                self.relogin { newToken in
                    if let newToken = newToken {
                        self.fetchEvents(token: newToken, allowRetry: false, completion: completion)
                    } else {
                        DispatchQueue.main.async { completion(nil) }
                    }
                }
                return
            }
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Best-effort acknowledgment report (fire and forget).
    func reportAck(eventId: String, title: String, kind: String) {
        guard let token = UserDefaults.standard.string(forKey: "aog_token") else { return }
        post(path: "functions/reportEventAck", token: token,
             body: ["event_id": eventId, "title": String(title.prefix(200)), "reminder_kind": kind]) { _, _ in }
    }

    private func relogin(completion: @escaping (String?) -> Void) {
        let email = UserDefaults.standard.string(forKey: "aog_email") ?? ""
        let password = UserDefaults.standard.string(forKey: "aog_password") ?? ""
        guard !email.isEmpty, !password.isEmpty else { completion(nil); return }
        post(path: "auth/login", token: nil, body: ["email": email, "password": password]) { data, status in
            var token: String?
            if status == 200, let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = obj["access_token"] as? String, !t.isEmpty {
                UserDefaults.standard.set(t, forKey: "aog_token")
                token = t
            }
            completion(token)
        }
    }

    private func post(path: String, token: String?, body: [String: Any],
                      completion: @escaping (Data?, Int) -> Void) {
        var request = URLRequest(url: base.appendingPathComponent("api/apps/\(appId)/\(path)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            completion(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }.resume()
    }
}
