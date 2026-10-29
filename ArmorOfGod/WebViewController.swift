import UIKit
import WebKit

/// The Armor of God web app (calendar, planner, everything) inside a native shell.
/// The native nav bar is HIDDEN on this screen - the web app has its own headers,
/// so a full-width "Armor of God" banner only stole space on every page.
/// The bell + reload live in one small floating button instead.
final class WebViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var fabButton: UIButton!
    private let siteURL = URL(string: "https://divine-armor-path.base44.app")!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Match the web app's dark background so any exposed edges blend in.
        view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

        webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            // Full screen inside the safe area: below the status bar, above the
            // home indicator. No nav bar anywhere on this screen.
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // The webview is already fully inside the safe area; don't let the
        // system add extra scroll insets on top of the app's own CSS spacing.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        setupFab()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep the banner gone, including when coming back from Phone Alarms.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // When an alarm gets acknowledged (slide-right), refresh the site so the
        // dashboard/XP reflects it immediately.
        NotificationCenter.default.addObserver(self, selector: #selector(ackCompleted),
                                               name: AppDelegate.ackReloadNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: AppDelegate.ackReloadNotification, object: nil)
    }

    @objc private func ackCompleted() {
        // Refresh the dashboard from origin after an acknowledgement.
        webView.reloadFromOrigin()
        NotificationScheduler.shared.syncAndSchedule()
    }

    /// Small translucent floating button, top-right corner. Tapping it opens a
    /// menu (Phone Alarms / Reload) instead of committing any screen space.
    private func setupFab() {
        fabButton = UIButton(type: .system)
        fabButton.translatesAutoresizingMaskIntoConstraints = false
        fabButton.setImage(UIImage(systemName: "bell.fill"), for: .normal)
        fabButton.tintColor = .white
        // FULLY OPAQUE, on purpose. This button floats over the web app's own
        // header, and a translucent circle let whatever is behind it (the site's
        // own bell/notification control) show through as a smudge that looked
        // like a rendering artifact. Solid fill + gold ring + a soft shadow so
        // it reads as one deliberate control, not a ghost of two.
        fabButton.backgroundColor = UIColor(red: 0.086, green: 0.094, blue: 0.114, alpha: 1.0)
        fabButton.layer.cornerRadius = 20
        fabButton.layer.borderWidth = 1.0
        fabButton.layer.borderColor = UIColor(red: 0.83, green: 0.69, blue: 0.29, alpha: 0.7).cgColor
        fabButton.layer.shadowColor = UIColor.black.cgColor
        fabButton.layer.shadowOpacity = 0.5
        fabButton.layer.shadowRadius = 6
        fabButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        fabButton.clipsToBounds = false
        fabButton.layer.masksToBounds = false
        fabButton.accessibilityLabel = "Alarm menu"
        fabButton.addTarget(self, action: #selector(openMenu), for: .touchUpInside)
        view.addSubview(fabButton)
        NSLayoutConstraint.activate([
            fabButton.widthAnchor.constraint(equalToConstant: 40),
            fabButton.heightAnchor.constraint(equalToConstant: 40),
            fabButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            fabButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }

    @objc private func openMenu() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Phone Alarms", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(AlarmSettingsViewController(), animated: true)
        })
        alert.addAction(UIAlertAction(title: "Reload Website", style: .default) { [weak self] _ in
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: "Diagnostics (alarm log)", style: .default) { [weak self] _ in
            // Let the action sheet finish dismissing before presenting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let diag = UINavigationController(rootViewController: DiagnosticsViewController())
                self?.present(diag, animated: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // Anchor the action sheet to the FAB so it pops from the corner on iPad too.
        if let popover = alert.popoverPresentationController {
            popover.sourceView = fabButton
            popover.sourceRect = fabButton.bounds
        }
        present(alert, animated: true)
    }

    private func reload() {
        // ALWAYS fetch the live site, never a cached copy. The web app is fixed and
        // redeployed from Base44 several times a day; a WKWebView that honours the
        // HTTP cache kept showing the OLD build after an app update, which looked
        // exactly like "still broken after the update".
        var request = URLRequest(url: siteURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        webView.load(request)
        NotificationScheduler.shared.syncAndSchedule()
    }
}


/// Read-only view of the alarm/ack breadcrumb log: bell button ->
/// "Diagnostics (alarm log)". Shows exactly which step the app died on.
final class DiagnosticsViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Alarm diagnostics"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self, action: #selector(close))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Copy", style: .plain,
                                                           target: self, action: #selector(copyLog))

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.text = AogDiag.tail(500)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func copyLog() {
        UIPasteboard.general.string = textView.text
        navigationItem.leftBarButtonItem?.title = "Copied"
    }
}


/// Root navigation controller. Its only job: while the alarm overlay is on
/// screen, the alarm owns the status bar so the clock face gets white text.
final class RootNavController: UINavigationController {
    weak var statusBarOwner: UIViewController?
    override var childForStatusBarStyle: UIViewController? {
        statusBarOwner ?? super.childForStatusBarStyle
    }
}
