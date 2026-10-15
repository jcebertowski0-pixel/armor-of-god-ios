import UIKit
import WebKit

/// The Armor of God web app (calendar, planner, everything) inside a native shell,
/// with a bell button for the alarm setup screen.
final class WebViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private let siteURL = URL(string: "https://divine-armor-path.base44.app")!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Armor of God"
        // Match the web app's dark background so any exposed edges blend in.
        view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

        // Lay the webview entirely INSIDE the safe area (below the nav bar /
        // status bar, above the home indicator). The previous full-bleed layout
        // let the nav bar cover the top of the web app on every screen, which
        // also made 100vh-based pages (Spartan Heart, Oracle chat screens) too
        // tall, hiding their input bars below the visible area.
        webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // The webview is already fully inside the safe area; don't let the
        // system add extra scroll insets on top of the app's own CSS spacing.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "bell.fill"), style: .plain,
            target: self, action: #selector(openAlarmSetup))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh, target: self, action: #selector(reload))
        reload()
    }

    @objc private func reload() {
        webView.load(URLRequest(url: siteURL))
        NotificationScheduler.shared.syncAndSchedule()
    }

    @objc private func openAlarmSetup() {
        navigationController?.pushViewController(AlarmSettingsViewController(), animated: true)
    }
}
