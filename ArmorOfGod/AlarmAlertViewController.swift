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
final class AlarmAlertViewController: UIViewController {

    private let event: PendingAlarm
    private let onAcknowledged: (PendingAlarm) -> Void

    private var player: AVAudioPlayer?
    private var vibrateTimer: Timer?
    private var pulseTimer: Timer?

    private let timeLabel = UILabel()
    private let titleLabel = UILabel()
    private let notesLabel = UILabel()
    private let kindLabel = UILabel()
    private let sliderTrack = UIView()
    private let sliderThumb = UIView()
    private let sliderHint = UILabel()
    private let knobLabel = UILabel()

    init(event: PendingAlarm, onAcknowledged: @escaping (PendingAlarm) -> Void) {
        self.event = event
        self.onAcknowledged = onAcknowledged
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.03, alpha: 1)
        buildUI()
        startRingtone()
        startVibration()
        startPulse()
        // In case we were opened from a dead state, kick a background sync so the
        // web app dashboard reflects the acknowledgment as soon as possible.
        NotificationScheduler.shared.syncAndSchedule()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRingtone()
        stopVibration()
    }

    // MARK: UI

    private func buildUI() {
        let clock = DateFormatter()
        clock.timeStyle = .short
        timeLabel.text = clock.string(from: event.firedAt)
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 80, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.5

        kindLabel.text = event.kind == "day_before" ? "TOMORROW'S EVENT"
                         : event.kind == "one_hour" ? "STARTS IN ONE HOUR"
                         : event.kind == "snooze" ? "SNOOZED REMINDER"
                         : "ALARM"
        kindLabel.font = .boldSystemFont(ofSize: 17)
        kindLabel.textColor = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
        kindLabel.textAlignment = .center

        titleLabel.text = "🔔 " + event.title
        titleLabel.font = .boldSystemFont(ofSize: 30)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        notesLabel.text = event.notes.isEmpty ? "" : event.notes
        notesLabel.font = .systemFont(ofSize: 18)
        notesLabel.textColor = UIColor(white: 0.75, alpha: 1)
        notesLabel.textAlignment = .center
        notesLabel.numberOfLines = 4

        for v in [timeLabel, kindLabel, titleLabel, notesLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        buildSlider()

        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 70),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            kindLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 10),
            kindLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            kindLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: kindLabel.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            notesLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            notesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            notesLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            sliderTrack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            sliderTrack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            sliderTrack.heightAnchor.constraint(equalToConstant: 84),
            sliderTrack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -70)
        ])
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
        sliderThumb.backgroundColor = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
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

        NSLayoutConstraint.activate([
            sliderThumb.leadingAnchor.constraint(equalTo: sliderTrack.leadingAnchor, constant: 4),
            sliderThumb.centerYAnchor.constraint(equalTo: sliderTrack.centerYAnchor),
            sliderThumb.widthAnchor.constraint(equalToConstant: 76),
            sliderThumb.heightAnchor.constraint(equalToConstant: 76),
            sliderHint.centerXAnchor.constraint(equalTo: sliderTrack.centerXAnchor),
            sliderHint.centerYAnchor.constraint(equalTo: sliderTrack.centerYAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panThumb(_:)))
        sliderThumb.addGestureRecognizer(pan)
    }

    private var dragging = false

    private var dragStartConstant: CGFloat = 4

    @objc private func panThumb(_ gr: UIPanGestureRecognizer) {
        guard !dragging else { return }
        let lead = sliderThumb.constraints.first { $0.firstAttribute == .leading }
        let resting: CGFloat = 4
        let travel = sliderTrack.bounds.width - 80
        switch gr.state {
        case .began:
            dragStartConstant = lead?.constant ?? resting
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            let x = gr.translation(in: sliderTrack).x
            lead?.constant = Swift.min(Swift.max(resting, dragStartConstant + x), travel)
            sliderHint.alpha = Swift.max(0, 1 - (lead?.constant ?? resting) / (travel * 0.6))
        case .ended, .cancelled:
            let reachedEnd = (lead?.constant ?? 0) >= sliderTrack.bounds.width - 82
            if reachedEnd {
                dragging = true
                acknowledge()
            } else {
                // Snap back to the start - no half-swipes allowed.
                lead?.constant = resting
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
            if let url = Bundle.main.url(forResource: "AlarmSound", withExtension: "wav") {
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

    // MARK: Vibration + pulse

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
