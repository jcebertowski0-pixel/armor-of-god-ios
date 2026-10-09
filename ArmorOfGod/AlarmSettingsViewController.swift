import UIKit

/// One-time setup screen for the alarm engine (bell button in the web view).
final class AlarmSettingsViewController: UIViewController {

    private let statusLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let permButton = UIButton(type: .system)
    private let signInButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)
    private let syncButton = UIButton(type: .system)
    private let testButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Phone Alarms"
        view.backgroundColor = .systemBackground
        setupUI()
        NotificationScheduler.shared.syncAndSchedule()
        refresh()
    }

    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [statusLabel, permButton, emailField, passwordField, signInButton,
                  signOutButton, syncButton, testButton] {
            stack.addArrangedSubview(v)
        }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 15)

        permButton.setTitle("1. Allow notifications (do this first)", for: .normal)
        permButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        permButton.addTarget(self, action: #selector(permTapped), for: .touchUpInside)

        emailField.placeholder = "2. Armor of God account email"
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.borderStyle = .roundedRect
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        signInButton.setTitle("Sign in", for: .normal)
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        signOutButton.setTitle("Sign out", for: .normal)
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)

        syncButton.setTitle("Sync now", for: .normal)
        syncButton.addTarget(self, action: #selector(syncTapped), for: .touchUpInside)
        testButton.setTitle("🔥 Test alarm in 15 seconds", for: .normal)
        testButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        testButton.addTarget(self, action: #selector(testTapped), for: .touchUpInside)
    }

    @objc private func permTapped() {
        NotificationScheduler.shared.requestAuthorization { ok in
            if !ok {
                self.statusLabel.text = "Notifications are OFF. Enable them in iPhone Settings → Notifications → Armor of God."
            }
            self.refresh()
        }
    }

    @objc private func signInTapped() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else { return }
        statusLabel.text = "Signing in…"
        AlarmSyncClient.shared.login(email: email, password: password) { error in
            if let error = error {
                self.statusLabel.text = error
            } else {
                self.passwordField.text = ""
                self.statusLabel.text = "Signed in — syncing events…"
                NotificationScheduler.shared.syncAndSchedule()
            }
            self.refresh()
        }
    }

    @objc private func signOutTapped() {
        AlarmSyncClient.shared.signOut()
        refresh()
    }

    @objc private func syncTapped() {
        statusLabel.text = "Syncing…"
        NotificationScheduler.shared.syncAndSchedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.refresh() }
    }

    @objc private func testTapped() {
        NotificationScheduler.shared.testAlarm()
        statusLabel.text = "Test alarm set — lock the phone and wait 15 seconds."
    }

    private func refresh() {
        let client = AlarmSyncClient.shared
        var text = ""
        if client.hasAccount {
            text = "Signed in as: \(client.email ?? "")\n"
            if let last = client.lastSync {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                text += "Last sync: \(f.string(from: last))\n"
            } else {
                text += "Not synced yet\n"
            }
        } else {
            text = "Not signed in. Sign in so calendar events fire on this phone.\n"
        }
        text += "\nNote: the iPhone mute switch silences alarm sounds — keep it off for can't-miss events."
        statusLabel.text = text
        let signedIn = client.hasAccount
        emailField.isHidden = signedIn
        passwordField.isHidden = signedIn
        signInButton.isHidden = signedIn
        signOutButton.isHidden = !signedIn
    }
}
