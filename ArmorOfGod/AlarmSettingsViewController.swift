import UIKit
import AVFoundation

/// The Phone Alarms screen: set an alarm, test it, pick a ringtone and an alarm
/// screen style. No sign-in required — that's tucked away as an optional
/// "calendar sync" section at the bottom for web-app events.
final class AlarmSettingsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()

    // Set-an-alarm
    private let datePicker = UIDatePicker()
    private let titleField = UITextField()
    private let dailySwitch = UISwitch()
    private let addAlarmButton = UIButton(type: .system)

    // Ringtone + style
    private let ringtoneControl = UISegmentedControl(items: ["Radar", "Siren", "Buzzer", "Bell"])
    private let styleControl = UISegmentedControl(items: ["Clock face", "Dark", "Red"])

    // Test
    private let testNowButton = UIButton(type: .system)
    private let testChainButton = UIButton(type: .system)

    // Optional calendar sync
    private let syncHint = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)
    private let syncNowButton = UIButton(type: .system)

    private var previewPlayer: AVAudioPlayer?
    private var previewStopTimer: Timer?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The web screen hides the nav bar; show it here so there's a back button.
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Phone Alarms"
        view.backgroundColor = .systemBackground
        setupUI()
        // One quiet permission ask on first visit — no step-by-step ceremony.
        NotificationScheduler.shared.requestAuthorization { ok in
            if !ok {
                self.statusLabel.text = "⚠️ Notifications are OFF — turn them on in iPhone Settings → Notifications → Armor of God."
            }
            self.refreshAlarms()
        }
        NotificationScheduler.shared.syncAndSchedule()
        refreshAlarms()
    }

    // MARK: UI

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(statusLabel)

        // -- SET AN ALARM ----------------------------------------------------
        stack.addArrangedSubview(sectionHeader("SET AN ALARM"))
        datePicker.datePickerMode = .time
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.heightAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(datePicker)

        titleField.placeholder = "What is it for? (e.g. Armor check-in)"
        titleField.borderStyle = .roundedRect
        titleField.autocapitalizationType = .none
        stack.addArrangedSubview(titleField)

        let dailyRow = UIStackView()
        dailyRow.axis = .horizontal
        dailyRow.spacing = 10
        dailySwitch.isOn = true
        let dailyLabel = UILabel()
        dailyLabel.text = "Repeat every day"
        dailyLabel.font = .systemFont(ofSize: 15)
        dailyRow.addArrangedSubview(dailyLabel)
        dailyRow.addArrangedSubview(dailySwitch)
        stack.addArrangedSubview(dailyRow)

        addAlarmButton.setTitle("➕ Add alarm", for: .normal)
        addAlarmButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        addAlarmButton.addTarget(self, action: #selector(addAlarmTapped), for: .touchUpInside)
        stack.addArrangedSubview(addAlarmButton)

        // -- RINGTONE --------------------------------------------------------
        stack.addArrangedSubview(sectionHeader("RINGTONE"))
        ringtoneControl.selectedSegmentIndex = NotificationScheduler.ringtones.firstIndex(of: NotificationScheduler.shared.ringtone) ?? 0
        ringtoneControl.addTarget(self, action: #selector(ringtoneChanged), for: .valueChanged)
        stack.addArrangedSubview(ringtoneControl)

        // -- ALARM SCREEN -----------------------------------------------------
        stack.addArrangedSubview(sectionHeader("ALARM SCREEN"))
        styleControl.selectedSegmentIndex = NotificationScheduler.styles.firstIndex(of: NotificationScheduler.shared.style) ?? 0
        styleControl.addTarget(self, action: #selector(styleChanged), for: .valueChanged)
        stack.addArrangedSubview(styleControl)

        // -- TEST -------------------------------------------------------------
        stack.addArrangedSubview(sectionHeader("TEST"))
        testNowButton.setTitle("🔥 Test alarm NOW", for: .normal)
        testNowButton.titleLabel?.font = .boldSystemFont(ofSize: 20)
        testNowButton.addTarget(self, action: #selector(testNowTapped), for: .touchUpInside)
        stack.addArrangedSubview(testNowButton)

        testChainButton.setTitle("Also test the locked-phone notification (rings in 15 s)", for: .normal)
        testChainButton.titleLabel?.font = .systemFont(ofSize: 13)
        testChainButton.setTitleColor(.secondaryLabel, for: .normal)
        testChainButton.addTarget(self, action: #selector(testChainTapped), for: .touchUpInside)
        stack.addArrangedSubview(testChainButton)

        // -- CALENDAR SYNC (optional) -----------------------------------------
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("CALENDAR SYNC (OPTIONAL)"))
        syncHint.numberOfLines = 0
        syncHint.font = .systemFont(ofSize: 13)
        syncHint.textColor = .secondaryLabel
        syncHint.text = "Sign in to also fire alarms from your Armor of God web app calendar events (day before + one hour before each event)."
        stack.addArrangedSubview(syncHint)

        emailField.placeholder = "Armor of God account email"
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.borderStyle = .roundedRect
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        stack.addArrangedSubview(emailField)
        stack.addArrangedSubview(passwordField)

        let syncRow = UIStackView()
        syncRow.axis = .horizontal
        syncRow.spacing = 20
        syncRow.distribution = .fillEqually
        signInButton.setTitle("Sign in", for: .normal)
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        signOutButton.setTitle("Sign out", for: .normal)
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        syncNowButton.setTitle("Sync now", for: .normal)
        syncNowButton.addTarget(self, action: #selector(syncNowTapped), for: .touchUpInside)
        syncRow.addArrangedSubview(signInButton)
        syncRow.addArrangedSubview(signOutButton)
        syncRow.addArrangedSubview(syncNowButton)
        stack.addArrangedSubview(syncRow)
    }

    private func sectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.backgroundColor = UIColor(white: 0.95, alpha: 1)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        return label
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    // MARK: Set alarm

    @objc private func addAlarmTapped() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: datePicker.date)
        NotificationScheduler.shared.addManual(title: titleField.text ?? "",
                                                hour: comps.hour ?? 0,
                                                minute: comps.minute ?? 0,
                                                daily: dailySwitch.isOn)
        titleField.text = ""
        refreshAlarms()
    }

    /// The list of set alarms (each with a delete button), inserted after the
    /// Add button so the owner sees what's armed.
    private var alarmRows: [UIView] = []

    private func refreshAlarms() {
        for row in alarmRows {
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        alarmRows.removeAll()

        let alarms = NotificationScheduler.shared.loadManual()
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        for (index, alarm) in alarms.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .center

            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            let timeL = UILabel()
            timeL.text = Calendar.current.date(from: comps).map { fmt.string(from: $0) }
                       ?? String(format: "%02d:%02d", alarm.hour, alarm.minute)
            timeL.font = .boldSystemFont(ofSize: 17)
            let titleL = UILabel()
            titleL.text = alarm.title + (alarm.daily ? "" : "  (once)")
            titleL.font = .systemFont(ofSize: 15)
            titleL.textColor = .secondaryLabel
            titleL.setContentHuggingPriority(.required, for: .horizontal)
            let deleteB = UIButton(type: .system)
            deleteB.setTitle("Delete", for: .normal)
            deleteB.setTitleColor(.systemRed, for: .normal)
            deleteB.tag = index
            deleteB.addTarget(self, action: #selector(deleteTapped(_:)), for: .touchUpInside)

            row.addArrangedSubview(timeL)
            row.addArrangedSubview(titleL)
            row.addArrangedSubview(deleteB)
            alarmRows.append(row)
        }
        // Rows appear right under the Add alarm button.
        if let addIndex = stack.arrangedSubviews.firstIndex(of: addAlarmButton) {
            for (offset, row) in alarmRows.enumerated() {
                stack.insertArrangedSubview(row, at: addIndex + 1 + offset)
            }
        }

        // Status line: account + last sync.
        let client = AlarmSyncClient.shared
        if client.hasAccount {
            var text = "Signed in as \(client.email ?? "")"
            if let last = client.lastSync {
                let f = DateFormatter()
                f.dateStyle = .short
                f.timeStyle = .short
                text += " · last sync \(f.string(from: last))"
            }
            statusLabel.text = text
        } else {
            statusLabel.text = "Manual alarms below work without an account."
        }
    }

    @objc private func deleteTapped(_ sender: UIButton) {
        let alarms = NotificationScheduler.shared.loadManual()
        guard sender.tag < alarms.count else { return }
        NotificationScheduler.shared.removeManual(id: alarms[sender.tag].id)
        refreshAlarms()
    }

    // MARK: Ringtone + style

    @objc private func ringtoneChanged() {
        let name = NotificationScheduler.ringtones[ringtoneControl.selectedSegmentIndex]
        NotificationScheduler.shared.setRingtone(name)
        preview(name)
    }

    /// Plays a few seconds of the selected ringtone so the owner can hear it.
    private func preview(_ name: String) {
        previewPlayer?.stop()
        previewStopTimer?.invalidate()
        let file = NotificationScheduler.soundFile(for: name)
        guard let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                                        withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.play()
            previewStopTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.previewPlayer?.stop()
                self?.previewPlayer = nil
            }
        } catch {
            NSLog("Preview failed: \(error)")
        }
    }

    @objc private func styleChanged() {
        NotificationScheduler.shared.setStyle(NotificationScheduler.styles[styleControl.selectedSegmentIndex])
    }

    // MARK: Test

    @objc private func testNowTapped() {
        (UIApplication.shared.delegate as? AppDelegate)?.presentTestAlarmNow()
    }

    @objc private func testChainTapped() {
        NotificationScheduler.shared.testAlarm()
        statusLabel.text = "Rings in 15 seconds — lock the phone, then tap the notification and slide right."
    }

    // MARK: Calendar sync (optional)

    @objc private func signInTapped() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else { return }
        statusLabel.text = "Signing in…"
        AlarmSyncClient.shared.login(email: email, password: password) { error in
            if let error = error {
                self.statusLabel.text = error
            } else {
                self.passwordField.text = ""
                NotificationScheduler.shared.syncAndSchedule()
            }
            self.refreshAlarms()
        }
    }

    @objc private func signOutTapped() {
        AlarmSyncClient.shared.signOut()
        NotificationScheduler.shared.syncAndSchedule()
        refreshAlarms()
    }

    @objc private func syncNowTapped() {
        statusLabel.text = "Syncing…"
        NotificationScheduler.shared.syncAndSchedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.refreshAlarms() }
    }
}
