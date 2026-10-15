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
    }

    /// Small translucent floating button, top-right corner. Tapping it opens a
    /// menu (Phone Alarms / Reload) instead of committing any screen space.
    private func setupFab() {
        fabButton = UIButton(type: .system)
        fabButton.translatesAutoresizingMaskIntoConstraints = false
        fabButton.setImage(UIImage(systemName: "bell.fill"), for: .normal)
        fabButton.tintColor = .white
        fabButton.backgroundColor = UIColor(white: 0.09, alpha: 0.65)
        fabButton.layer.cornerRadius = 20
        fabButton.layer.borderWidth = 0.5
        fabButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
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
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // Anchor the action sheet to the FAB so it pops from the corner on iPad too.
        if let popover = alert.popoverPresentationController {
            popover.sourceView = fabButton
            popover.sourceRect = fabButton.bounds
        }
        present(alert, animated: true)
    }

    private func reload() {
        webView.load(URLRequest(url: siteURL))
        NotificationScheduler.shared.syncAndSchedule()
    }
}
