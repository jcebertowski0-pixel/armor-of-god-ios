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
        view.backgroundColor = .white

        webView = WKWebView(frame: view.bounds)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

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
