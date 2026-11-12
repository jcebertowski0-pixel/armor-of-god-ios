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

        // The web build positions its top header with `position: fixed`, which
        // takes it out of the layout flow: on every page except Home the first
        // ~60px of content slides underneath it and gets clipped (Home survives
        // because its first block is a full-bleed hero). The permanent fix is a
        // published web build that pads the scroll area, but this shell must stay
        // correct no matter which bundle the site is serving, so inject a tiny
        // guard that puts that header back into the flow while the page it is on
        // would otherwise be clipped. It self-disables the moment the web app
        // ships its own offset (padding >= 40px) and never touches Home.
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.headerGuardScript,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true))
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.voiceBridgeScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        configuration.userContentController.add(VoiceBridge.shared, name: "aogVoice")

        webView = WKWebView(frame: .zero, configuration: configuration)
        VoiceBridge.shared.attach(webView)
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
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                              name: UIApplication.didBecomeActiveNotification,
                                              object: nil)
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

    /// The site is redeployed from Base44 several times a day. Reload it whenever
    /// the app comes back to the foreground (max once every 30s) so a fresh
    /// deploy shows up without a force-quit.
    @objc private func appBecameActive() {
        guard Date().timeIntervalSince(lastReloadAt) > 30 else { return }
        lastReloadAt = Date()
        webView.reloadFromOrigin()
        NotificationScheduler.shared.syncAndSchedule()
    }

    /// The web app draws TWO fixed bars on most screens: the shell's own header
    /// (avatar + bell, z-55) and the page's title bar (PageHeader, z-56). Inside
    /// WKWebView the page bar is trapped in the scroll container's stacking
    /// context, so it paints BENEATH the shell header and its title gets cut in
    /// half ("Spartan / Weightlifting" with the first line hidden behind the
    /// avatar bar). Home has no page bar, which is why every other tab was hit.
    ///
    /// Fix: as soon as a screen supplies its own title bar, hide the shell header
    /// so nothing can paint over the title. The shell header is position:fixed, so
    /// hiding it reflows nothing; the page's own bar becomes the only bar, and the
    /// web app's --spartan-header-h padding already keeps content clear of it.
    /// Also neutralises the iOS scroll layer that traps fixed descendants, and
    /// backs out cleanly on screens with no page bar (Home).
    private static let headerGuardScript = """
    (function(){
      if (window.__aogHeaderGuard) { return; }
      window.__aogHeaderGuard = true;
      var STYLE_ID = 'aog-header-guard';
      var FLAG = 'data-aog-pagebar';
      var BAR_ATTR = 'data-aog-titlebar';
      function injectStyle(){
        if (document.getElementById(STYLE_ID)) { return; }
        var el = document.createElement('style');
        el.id = STYLE_ID;
        el.textContent =
          'html[' + FLAG + '] header.fixed:not([' + BAR_ATTR + ']){display:none !important;}' +
          'div.overflow-y-auto{-webkit-overflow-scrolling:auto !important;}' +
          '[' + BAR_ATTR + ']{z-index:9999 !important;}';
        (document.head || document.documentElement).appendChild(el);
      }
      function scroller(){
        return document.querySelector('header.fixed ~ div.overflow-y-auto');
      }
      function titleBar(sc){
        var cands = sc.querySelectorAll('div.fixed.top-0');
        for (var i = 0; i < cands.length; i++) {
          var b = cands[i];
          var r = b.getBoundingClientRect();
          if (r.width > 100 && b.querySelector('h1')) { return b; }
        }
        return null;
      }
      function apply(){
        try {
          injectStyle();
          var root = document.documentElement;
          var sc = scroller();
          var bar = sc ? titleBar(sc) : null;
          if (bar) {
            bar.setAttribute(BAR_ATTR, '1');
            if (!root.hasAttribute(FLAG)) { root.setAttribute(FLAG, '1'); }
          } else if (root.hasAttribute(FLAG)) {
            root.removeAttribute(FLAG);
          }
        } catch (e) {}
      }
      apply();
      document.addEventListener('DOMContentLoaded', apply);
      window.addEventListener('load', apply);
      try {
        new MutationObserver(apply).observe(document.documentElement,
          {childList: true, subtree: true, attributes: true, attributeFilter: ['aria-current']});
      } catch (e) {}
      setInterval(apply, 1000);
    })();
    """

    /// Exposes the native voice layer to the web app as `window.AOGVoice`.
    /// `listen()` resolves with a transcript, `speak(text)` reads a reply aloud,
    /// `stop()`/`stopSpeaking()` cut either off. It also hands the page's Base44
    /// access token to the shell so Siri shortcuts work while the app is closed.
    private static let voiceBridgeScript = """
    (function(){
      var handlers = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.aogVoice;
      if (!handlers) { return; }
      function post(obj){ try { handlers.postMessage(obj); } catch(e){} }
      var bridge = {
        available: true,
        onPartial: null,
        onSpeakEnd: null,
        _pending: null,
        _native: function(m){
          try {
            if (m.type === 'partial') {
              if (bridge.onPartial) { bridge.onPartial(m.text); }
            } else if (m.type === 'final') {
              var done = bridge._pending; bridge._pending = null;
              if (done) { done.resolve(m.text); }
            } else if (m.type === 'error') {
              var failed = bridge._pending; bridge._pending = null;
              if (failed) { failed.reject(new Error(m.message || 'voice error')); }
            } else if (m.type === 'speakEnd') {
              if (bridge.onSpeakEnd) { bridge.onSpeakEnd(); }
            }
          } catch(e){}
        },
        listen: function(){
          return new Promise(function(resolve, reject){
            if (bridge._pending) { try { bridge._pending.reject(new Error('replaced')); } catch(e){} }
            bridge._pending = null;
            var settled = false;
            var timer = setTimeout(function(){
              if (settled) { return; }
              settled = true; bridge._pending = null;
              reject(new Error('Voice input timed out. Tap the mic and try again.'));
            }, 20000);
            function done(text){ if (settled) { return; } settled = true; clearTimeout(timer); bridge._pending = null; resolve(text); }
            function fail(err){ if (settled) { return; } settled = true; clearTimeout(timer); bridge._pending = null; reject(err); }
            bridge._pending = { resolve: done, reject: fail };
            try { post({ action: 'listen' }); } catch(e){ fail(e); }
          });
        },
        stop: function(){ post({ action: 'stop' }); },
        speak: function(text){ if (text) { post({ action: 'speak', text: String(text) }); } },
        stopSpeaking: function(){ post({ action: 'stopSpeaking' }); },
        _pushToken: function(){
          try {
            var t = localStorage.getItem('base44_access_token') || localStorage.getItem('token');
            if (t) { post({ action: 'token', token: t }); }
          } catch(e){}
        }
      };
      window.AOGVoice = bridge;
      bridge._pushToken();
      window.addEventListener('load', function(){ bridge._pushToken(); });
      setInterval(function(){ bridge._pushToken(); }, 5000);
    })();
    """

    private var lastReloadAt = Date()

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
