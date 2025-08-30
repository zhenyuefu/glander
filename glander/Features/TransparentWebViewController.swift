import AppKit
import WebKit

final class TransparentWebViewController: NSViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    // Controls injecting CSS to force transparent page background; off by default.
    var transparencyCSSEnabled: Bool = false { didSet { applyBackgroundTransparencyIfReady() } }
    var customUserAgent: String? { didSet { applyCustomUserAgentIfReady() } }

    override func loadView() {
        let cfg = WebKitConfig.make(ephemeral: Preferences.shared.useEphemeralWebSession)

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Only make WKWebView background transparent when CSS transparency is enabled.
        webView.setValue(!transparencyCSSEnabled, forKey: "drawsBackground")
        self.webView = webView

        // Apply any custom UA set before the view was loaded
        applyCustomUserAgentIfReady()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        self.view = container
        // Provide a non-zero preferred size so the window does not
        // collapse to 0x0 when this VC becomes contentViewController.
        // The window remains resizable by the user.
        if self.preferredContentSize == .zero {
            self.preferredContentSize = NSSize(width: 900, height: 600)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        webView.frame = view.bounds
    }

    func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    func loadHTML(_ html: String) {
        // 提供非空的 baseURL，避免 WebKit 某些子进程输出 null URL 噪音
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: base)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard transparencyCSSEnabled else { return }
        injectTransparencyCSS()
    }

    private func injectTransparencyCSS() {
        let css = """
        html, body { background: transparent !important; }
        * { background-color: transparent !important; }
        """
        let js = """
        (function(){
          var style = document.createElement('style');
          style.type = 'text/css';
          style.appendChild(document.createTextNode(`\(css)`));
          document.documentElement.appendChild(style);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func evaluateJS(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Helpers
    private func applyCustomUserAgentIfReady() {
        guard isViewLoaded, webView != nil else { return }
        webView.customUserAgent = (customUserAgent?.isEmpty == false) ? customUserAgent : nil
    }

    private func applyBackgroundTransparencyIfReady() {
        guard isViewLoaded, webView != nil else { return }
        webView.setValue(!transparencyCSSEnabled, forKey: "drawsBackground")
    }
}
