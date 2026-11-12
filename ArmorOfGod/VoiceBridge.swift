import AVFoundation
import Foundation
import Speech
import WebKit

/// Where the web session's Base44 access token is kept so Siri intents can reach
/// the API while the app is closed. Written by the page (see voiceBridgeScript in
/// WebViewController) and read by VoiceIntents.
final class VoiceTokenStore {
    static let shared = VoiceTokenStore()
    private let key = "aog_web_token"

    var token: String? {
        get {
            guard let t = UserDefaults.standard.string(forKey: key), !t.isEmpty else { return nil }
            return t
        }
        set {
            if let t = newValue, !t.isEmpty {
                UserDefaults.standard.set(t, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// Native half of the app's voice controls.
///
/// The web app talks to this through `window.AOGVoice` (injected at document
/// start): `listen()` resolves with a transcript, `speak(text)` reads a reply
/// aloud, `stop()`/`stopSpeaking()` cut either one off. Speech recognition and
/// synthesis are Apple's on-device engines - they are free, work offline and
/// route through whatever earbuds are connected, which is the whole point of the
/// feature (hear the app in your earbuds on the way through the morning).
final class VoiceBridge: NSObject, WKScriptMessageHandler, SFSpeechRecognizerDelegate,
                        AVSpeechSynthesizerDelegate {

    static let shared = VoiceBridge()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    private var tapInstalled = false
    private var lastTranscript = ""
    private weak var webView: WKWebView?
    private var watchdog: Timer?

    override init() {
        super.init()
        synth.delegate = self
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - JS -> native

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        if let view = message.webView { self.webView = view }
        AogDiag.log("voice: \(action)")

        switch action {
        case "token":
            if let t = body["token"] as? String { VoiceTokenStore.shared.token = t }
        case "listen":
            startListening()
        case "stop":
            stopListening(emitFinal: true)
        case "speak":
            if let text = body["text"] as? String { speak(text) }
        case "stopSpeaking":
            synth.stopSpeaking(at: .immediate)
        default:
            break
        }
    }

    // MARK: - Listening

    private func startListening() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            emit(["type": "error", "message": "Speech recognition is not available right now."])
            return
        }
        if engine.isRunning { stopListening(emitFinal: false) }
        armWatchdog()
        AogDiag.log("voice: startListening speech=\(SFSpeechRecognizer.authorizationStatus().rawValue) mic=\(AVAudioSession.sharedInstance().recordPermission.rawValue)")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            guard status == .authorized else {
                self.emit(["type": "error", "message": "Microphone access for speech is off. Turn it on in Settings > Armor of God."])
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                AogDiag.log("voice: mic granted=\(granted)")
                guard granted else {
                    self.emit(["type": "error", "message": "Microphone access is off. Turn it on in Settings > Armor of God."])
                    return
                }
                DispatchQueue.main.async { self.beginSession(recognizer) }
            }
        }
    }

    private func beginSession(_ recognizer: SFSpeechRecognizer) {
        stopListening(emitFinal: false)
        lastTranscript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            emit(["type": "error", "message": "Could not start the microphone."])
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            AogDiag.log("voice: bad input format \(format.sampleRate)Hz/\(format.channelCount)ch")
            stopListening(emitFinal: false)
            emit(["type": "error", "message": "The microphone is not ready. Tap the mic again."])
            return
        }
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            tapInstalled = true
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopListening(emitFinal: false)
            emit(["type": "error", "message": "Could not start the microphone."])
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                if result.isFinal {
                    self.finish(with: text, error: nil)
                } else {
                    self.emit(["type": "partial", "text": text])
                }
            } else if let error = error {
                self.finish(with: self.lastTranscript, error: error)
            }
        }
    }

    /// The page's promise only settles on a final or an error, so a stuck audio
    /// session used to leave the mic button spinning forever. This guarantees an
    /// answer either way.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            AogDiag.log("voice: watchdog fired running=\(self.engine.isRunning) task=\(self.task != nil)")
            if self.task != nil || self.engine.isRunning {
                self.finish(with: self.lastTranscript,
                            error: NSError(domain: "aog.voice", code: -1,
                                           userInfo: [NSLocalizedDescriptionKey: "timed out"]))
            } else {
                self.stopListening(emitFinal: false)
                self.emit(["type": "error",
                           "message": "The microphone did not start. Check Settings > Armor of God > Microphone."])
            }
        }
    }

    private func stopListening(emitFinal: Bool) {
        watchdog?.invalidate()
        watchdog = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if emitFinal { finish(with: lastTranscript, error: nil) }
    }

    private func finish(with text: String, error: Error?) {
        let wasListening = task != nil || engine.isRunning
        stopListening(emitFinal: false)
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            emit(["type": "error", "message": error == nil
                  ? "I didn't catch that."
                  : "I didn't catch that. Try again."])
        } else {
            emit(["type": "final", "text": clean])
        }
        if wasListening && engine.isRunning { engine.stop() }
    }

    // MARK: - Speaking

    private func speak(_ text: String) {
        stopListening(emitFinal: false)
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Keep going: AVSpeechSynthesizer still speaks on the default route.
        }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
        emit(["type": "speakStart"])
    }

    /// Markdown and emoji read badly out loud, so strip them before speaking.
    static func speakable(_ text: String) -> String {
        var s = text
        let strip: [(String, String)] = [
            ("**", ""), ("__", ""), ("`", ""), ("#", ""), ("*", ""), (">", ""),
            ("|", " "), ("[", ""), ("]", ""), ("_", " ")
        ]
        for (from, to) in strip { s = s.replacingOccurrences(of: from, with: to) }
        s = s.replacingOccurrences(of: "\n", with: ". ")
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        emit(["type": "speakEnd"])
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        emit(["type": "speakEnd"])
    }

    // MARK: - Results back to the page

    private func emit(_ payload: [String: Any]) {
        if webView == nil { AogDiag.log("voice: emit dropped, no webview (\(payload["type"] ?? "?"))") }
        guard let webView = webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.AOGVoice && window.AOGVoice._native && window.AOGVoice._native(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
