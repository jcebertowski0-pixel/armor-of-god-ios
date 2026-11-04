import AppIntents
import Foundation

/// The commands the web app's `voiceAssistant` function understands.
enum VoiceCommand: String {
    case routine
    case workout
    case reflection
    case alarms
    case birthday
    case logExpense = "log_expense"
    case logIncome = "log_income"

    /// Siri hands over whatever the user said, so map loose wording onto a command.
    static func from(_ text: String) -> VoiceCommand {
        let t = text.lowercased()
        if t.contains("income") || t.contains("earn") || t.contains("got paid") { return .logIncome }
        if t.contains("spent") || t.contains("expense") || t.contains("spend") { return .logExpense }
        if t.contains("birthday") || t.contains("born") { return .birthday }
        if t.contains("alarm") || t.contains("calendar") || t.contains("coming up") { return .alarms }
        if t.contains("reflection") || t.contains("devotional") || t.contains("scripture") { return .reflection }
        if t.contains("workout") || t.contains("lift") || t.contains("train") { return .workout }
        if t.contains("routine") || t.contains("disciplin") { return .routine }
        return .routine
    }
}

/// Talks to the web app's `voiceAssistant` backend function with the access token
/// the page handed us, and returns one speakable sentence.
struct VoiceAssistantClient {
    static let base = URL(string: "https://divine-armor-path.base44.app")!
    static let appId = "69b073d713d45657aef116c5"

    static func ask(_ command: VoiceCommand,
                    amount: Double? = nil,
                    note: String? = nil) async -> String {
        guard let token = VoiceTokenStore.shared.token else {
            return "Open Armor of God and sign in once, then ask me again."
        }
        var request = URLRequest(
            url: base.appendingPathComponent("api/apps/\(appId)/functions/voiceAssistant"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["command": command.rawValue]
        if let amount = amount { body["amount"] = amount }
        if let note = note, !note.isEmpty { body["note"] = note }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let speech = obj["speech"] as? String,
               !speech.isEmpty {
                return speech
            }
        } catch {
            // Fall through to the friendly line below.
        }
        return "I couldn't reach Armor of God just now. Try again in a moment."
    }
}

// MARK: - Intents
//
// iOS only lets a third-party app answer Siri when the phrase names the app, so
// every shortcut below is "Hey Siri, ... in Armor of God". Inside the app the mic
// button needs no wake word at all.

struct AskArmorOfGodIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Armor of God"
    static var description = IntentDescription(
        "Ask about your routine, workout, daily reflection, upcoming alarms or next birthday.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask Armor of God?")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(VoiceCommand.from(question))
        return .result(dialog: "\(answer)")
    }
}

struct RoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask about my routine"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.routine)
        return .result(dialog: "\(answer)")
    }
}

struct WorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask about my workout"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.workout)
        return .result(dialog: "\(answer)")
    }
}

struct ReflectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Hear my daily reflection"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.reflection)
        return .result(dialog: "\(answer)")
    }
}

struct AlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask what alarms are coming up"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.alarms)
        return .result(dialog: "\(answer)")
    }
}

struct BirthdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask whose birthday is next"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.birthday)
        return .result(dialog: "\(answer)")
    }
}

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an expense"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", requestValueDialog: "How much did you spend?")
    var amount: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.logExpense, amount: amount)
        return .result(dialog: "\(answer)")
    }
}

struct LogIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log income"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", requestValueDialog: "How much income?")
    var amount: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await VoiceAssistantClient.ask(.logIncome, amount: amount)
        return .result(dialog: "\(answer)")
    }
}

struct ArmorOfGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Siri only accepts AppEnum/AppEntity values inside a phrase, so this one
        // asks for the question out loud instead of trying to parse it inline
        // ("What do you want to ask Armor of God?").
        AppShortcut(intent: AskArmorOfGodIntent(),
                    phrases: ["Ask \(.applicationName) a question"],
                    shortTitle: "Ask Armor of God",
                    systemImageName: "shield.lefthalf.filled")
        AppShortcut(intent: RoutineIntent(),
                    phrases: ["What's my routine in \(.applicationName)"],
                    shortTitle: "My routine",
                    systemImageName: "checklist")
        AppShortcut(intent: WorkoutIntent(),
                    phrases: ["What's my workout in \(.applicationName)"],
                    shortTitle: "My workout",
                    systemImageName: "figure.strengthtraining.traditional")
        AppShortcut(intent: ReflectionIntent(),
                    phrases: ["What's my daily reflection in \(.applicationName)"],
                    shortTitle: "Daily reflection",
                    systemImageName: "book")
        AppShortcut(intent: AlarmsIntent(),
                    phrases: ["What alarms are coming up in \(.applicationName)"],
                    shortTitle: "Upcoming alarms",
                    systemImageName: "alarm")
        AppShortcut(intent: BirthdayIntent(),
                    phrases: ["Whose birthday is next in \(.applicationName)"],
                    shortTitle: "Next birthday",
                    systemImageName: "gift")
        AppShortcut(intent: LogExpenseIntent(),
                    phrases: ["Log an expense in \(.applicationName)"],
                    shortTitle: "Log an expense",
                    systemImageName: "dollarsign.circle")
        AppShortcut(intent: LogIncomeIntent(),
                    phrases: ["Log income in \(.applicationName)"],
                    shortTitle: "Log income",
                    systemImageName: "arrow.down.circle")
    }
}
