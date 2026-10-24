import UIKit
import AVFoundation
import AudioToolbox

/// Full-screen, Clock-style alarm takeover: loud looping ringtone (plays even on
/// the silent switch), repeated vibration, and a SLIDE-TO-ACKNOWLEDGE slider that
/// is the ONLY way out. No buttons, no tap-to-dismiss, no escape — the slider
/// must be dragged all the way to the right, exactly like stopping an iPhone
/// Clock alarm. Presented any time an alarm fires while the app is open, when a
/// notification is tapped, and when the app is opened with an unacknowledged
/// (missed) alarm — however late that happens.
///
/// Styles (picked on the Phone Alarms screen):
///  - "clock": the big live digital clock face — giant "05:47 AM" ticking in
///    real time, like the phone in the app's Phone Alarms tile.
///  - "dark": big event time + title on black.
///  - "red": same layout, war-room red.
final class AlarmAlertViewController: UIViewController {

    private let event: PendingAlarm
    private let onAcknowledged: (PendingAlarm) -> Void
    private let style: String

    private var player: AVAudioPlayer?
    private var vibrateTimer: Timer?
    private var pulseTimer: Timer?
    private var clockTimer: Timer?

    private let timeLabel = UILabel()
    private let dateLabel = UILabel()
    private let kindLabel = UILabel()
    private let eventCard = UIView()
    private let titleLabel = UILabel()
    private let notesLabel = UILabel()
    private let sliderTrack = UIView()
    private let sliderThumb = UIView()
    private let sliderHint = UILabel()
    private let knobLabel = UILabel()

    private let accent: UIColor
    private let bg: UIColor

    init(event: PendingAlarm, onAcknowledged: @escaping (PendingAlarm) -> Void) {
        self.event = event
        self.onAcknowledged = onAcknowledged
        self.style = NotificationScheduler.shared.style
        if style == "red" {
            accent = UIColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1)
            bg = UIColor(red: 0.12, green: 0.02, blue: 0.02, alpha: 1)
        } else {
            // Clock face and dark share the black canvas + alarm-orange knob.
            accent = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
            bg = UIColor(white: 0.03, alpha: 1)
        }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        buildUI()
        startRingtone()
        startVibration()
        startPulse()
        if style == "clock" { startClock() }
        // In case we were opened from a dead state, kick a background sync so the
        // web app dashboard reflects the acknowledgment as soon as possible.
        NotificationScheduler.shared.syncAndSchedule()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRingtone()
        stopVibration()
    }

    /// "lead_30" -> "STARTS IN 30 MINUTES" etc.
    private func leadText(_ kind: String) -> String {
        guard let m = Int(kind.dropFirst(5)) else { return "ALARM" }
        if m >= 1440 { return m / 1440 == 1 ? "TOMORROW'S EVENT" : "IN \(m / 1440) DAYS" }
        if m >= 60 { return m == 60 ? "STARTS IN ONE HOUR" : "STARTS IN \(m / 60) HOURS" }
        return "STARTS IN \(m) MINUTES"
    }

    // MARK: UI

    private func buildUI() {
        for v in [timeLabel, kindLabel, eventCard, titleLabel, notesLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        if style == "clock" {
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(dateLabel)
        }

        eventCard.backgroundColor = UIColor(white: 0.10, alpha: 1)
        eventCard.layer.cornerRadius = 18
        eventCard.addSubview(titleLabel)
        eventCard.addSubview(notesLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        notesLabel.translatesAutoresizingMaskIntoConstraints = false

        let clockFmt = DateFormatter()
        clockFmt.dateFormat = "hh:mm a"

        if style == "clock" {
            // The big live digital clock: "05:47 AM" like the Clock app.
            timeLabel.text = clockFmt.string(from: Date())
            timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 92, weight: .medium)
            timeLabel.textColor = .white
            timeLabel.textAlignment = .center
            timeLabel.adjustsFontSizeToFitWidth = true
            timeLabel.minimumScaleFactor = 0.4

            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "EEEE, MMM d"
            dateLabel.text = dayFmt.string(from: Date())
            dateLabel.font = .systemFont(ofSize: 19)
            dateLabel.textColor = UIColor(white: 0.65, alpha: 1)
            dateLabel.textAlignment = .center

            kindLabel.text = "ALARM"
            kindLabel.font = .boldSystemFont(ofSize: 15)
            kindLabel.textColor = accent
            kindLabel.textAlignment = .center
        } else {
            let firedFmt = DateFormatter()
            firedFmt.timeStyle = .short
            timeLabel.text = firedFmt.string(from: event.firedAt)
            timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 80, weight: .medium)
            timeLabel.textColor = .white
            timeLabel.textAlignment = .center
            timeLabel.adjustsFontSizeToFitWidth = true
            timeLabel.minimumScaleFactor = 0.5

            kindLabel.text = event.kind.hasPrefix("lead_")
                             ? leadText(event.kind)
                             : event.kind == "snooze" ? "SNOOZED REMINDER"
                             : event.kind == "manual" ? "YOUR ALARM"
                             : "ALARM"
            kindLabel.font = .boldSystemFont(ofSize: 17)
            kindLabel.textColor = accent
            kindLabel.textAlignment = .center
        }

        titleLabel.text = event.title.isEmpty ? "Armor of God" : "🔔 " + event.title
        titleLabel.font = .boldSystemFont(ofSize: 26)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        notesLabel.text = event.notes.isEmpty ? "" : event.notes
        notesLabel.font = .systemFont(ofSize: 16)
        notesLabel.textColor = UIColor(white: 0.72, alpha: 1)
        notesLabel.textAlignment = .center
        notesLabel.numberOfLines = 4

        buildSlider()

        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                           constant: style == "clock" ? 90 : 70),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            kindLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            kindLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            eventCard.topAnchor.constraint(equalTo: kindLabel.bottomAnchor, constant: 28),
            eventCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            eventCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: eventCard.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: eventCard.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: eventCard.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: notesLabel.topAnchor, constant: -4),
            notesLabel.leadingAnchor.constraint(equalTo: eventCard.leadingAnchor, constant: 16),
            notesLabel.trailingAnchor.constraint(equalTo: eventCard.trailingAnchor, constant: -16),
            notesLabel.bottomAnchor.constraint(equalTo: eventCard.bottomAnchor, constant: -16),

            sliderTrack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            sliderTrack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            sliderTrack.heightAnchor.constraint(equalToConstant: 84),
            sliderTrack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -70)
        ])

        if style == "clock" {
            NSLayoutConstraint.activate([
                dateLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 2),
                dateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                kindLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 14)
            ])
        } else {
            NSLayoutConstraint.activate([
                kindLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 10)
            ])
        }
    }

    /// The swipe-right-to-acknowledge slider: iPhone unlock / Clock stop style.
    private func buildSlider() {
        sliderTrack.translatesAutoresizingMaskIntoConstraints = false
        sliderTrack.backgroundColor = UIColor(white: 0.13, alpha: 1)
        sliderTrack.layer.cornerRadius = 42
        view.addSubview(sliderTrack)

        sliderHint.text = "slide to acknowledge →"
        sliderHint.font = .boldSystemFont(ofSize: 20)
        sliderHint.textColor = UIColor(white: 0.62, alpha: 1)
        sliderHint.textAlignment = .center
        sliderHint.translatesAutoresizingMaskIntoConstraints = false
        sliderTrack.addSubview(sliderHint)

        sliderThumb.translatesAutoresizingMaskIntoConstraints = false
        sliderThumb.backgroundColor = accent
        sliderThumb.layer.cornerRadius = 38
        sliderThumb.isUserInteractionEnabled = true
        sliderTrack.addSubview(sliderThumb)

        knobLabel.text = "⟩⟩"
        knobLabel.font = .boldSystemFont(ofSize: 26)
        knobLabel.textColor = UIColor(white: 0.1, alpha: 1)
        knobLabel.textAlignment = .center
        knobLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderThumb.addSubview(knobLabel)
        NSLayoutConstraint.activate([
            knobLabel.centerXAnchor.constraint(equalTo: sliderThumb.centerXAnchor),
            knobLabel.centerYAnchor.constraint(equalTo: sliderThumb.centerYAnchor)
        ])

        // Strong stored reference to the knob's leading constraint. NEVER look it
        // up through view.constraints again - that lookup could miss and left
        // the knob completely unresponsive to drags (alarm could not be
        // acknowledged at all).
        sliderLead = sliderThumb.leadingAnchor.constraint(equalTo: sliderTrack.leadingAnchor, constant: 4)
        NSLayoutConstraint.activate([
            sliderLead,
            sliderThumb.centerYAnchor.constraint(equalTo: sliderTrack.centerYAnchor),
            sliderThumb.widthAnchor.constraint(equalToConstant: 76),
            sliderThumb.heightAnchor.constraint(equalToConstant: 76),
            sliderHint.centerXAnchor.constraint(equalTo: sliderTrack.centerXAnchor),
            sliderHint.centerYAnchor.constraint(equalTo: sliderTrack.centerYAnchor)
        ])

        // The recognizer lives on the TRACK, not the little knob: the whole
        // slider responds to a finger. Grabbing anywhere pulls the knob there.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panThumb(_:)))
        sliderTrack.addGestureRecognizer(pan)
    }

    private var sliderLead: NSLayoutConstraint!
    private var dragging = false
    private var dragStartConstant: CGFloat = 4

    @objc private func panThumb(_ gr: UIPanGestureRecognizer) {
        let resting: CGFloat = 4
        let trackW = sliderTrack.bounds.width
        guard trackW > 0, sliderLead != nil, !dragging else { return }
        let travel = trackW - 80   // knob width 76 + 4pt margins each side
        switch gr.state {
        case .began:
            // Grab anywhere in the track: center the knob under the finger.
            let x = gr.location(in: sliderTrack).x - 38
            dragStartConstant = Swift.min(Swift.max(resting, x), travel)
            sliderLead.constant = dragStartConstant
            sliderTrack.layoutIfNeeded()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            let x = gr.translation(in: sliderTrack).x
            sliderLead.constant = Swift.min(Swift.max(resting, dragStartConstant + x), travel)
            sliderHint.alpha = Swift.max(0, 1 - sliderLead.constant / (travel * 0.6))
            sliderTrack.layoutIfNeeded()   // follow the finger in this frame
        case .ended, .cancelled:
            if sliderLead.constant >= travel {
                dragging = true
                acknowledge()
            } else {
                // Snap back to the start - no half-swipes allowed.
                sliderLead.constant = resting
                sliderHint.alpha = 1
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.sliderTrack.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }

    /// The ONLY exit path from this screen.
    private func acknowledge() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        stopRingtone()
        stopVibration()
        let callback = onAcknowledged
        dismiss(animated: true) {
            callback(self.event)
            // Let the app show the next missed alarm, if any.
            (UIApplication.shared.delegate as? AppDelegate)?.alarmScreenDidFinish()
        }
    }

    // MARK: Ringtone

    private func startRingtone() {
        do {
            // .playback ignores the physical silent switch — a real alarm.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let file = NotificationScheduler.soundFile(for: NotificationScheduler.shared.ringtone)
            if let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                                          withExtension: "wav") {
                player = try AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = -1
                player?.volume = 1.0
                player?.play()
            }
        } catch {
            NSLog("Alarm ringtone failed: \(error)")
        }
    }

    private func stopRingtone() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Vibration + pulse + live clock

    private func startVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopVibration() {
        vibrateTimer?.invalidate()
        vibrateTimer = nil
    }

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.25, animations: {
                self.kindLabel.alpha = self.kindLabel.alpha > 0.5 ? 0.35 : 1.0
            })
        }
    }

    /// Ticks the big clock face every second, like the Clock app.
    private func startClock() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let fmt = DateFormatter()
            fmt.dateFormat = "hh:mm a"
            self.timeLabel.text = fmt.string(from: Date())
        }
    }
}

/// An alarm that has fired (or was missed) and still demands a swipe.
struct PendingAlarm: Equatable {
    let id: String
    let title: String
    let notes: String
    let kind: String
    let firedAt: Date

    static func == (l: PendingAlarm, r: PendingAlarm) -> Bool {
        l.id == r.id && l.kind == r.kind && l.firedAt == r.firedAt
    }
}
