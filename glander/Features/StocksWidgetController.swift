import AppKit
import WebKit

final class StocksWidgetController: NSViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    var symbols: [String] = [] { didSet { reload() } }
    var darkTheme: Bool = true { didSet { reload() } }

    override func loadView() {
        let cfg = WebKitConfig.make(ephemeral: Preferences.shared.useEphemeralWebSession)
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        webView = wv

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        wv.frame = container.bounds
        wv.autoresizingMask = [.width, .height]
        container.addSubview(wv)
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        webView.frame = view.bounds
    }

    func reload() {
        guard isViewLoaded else { return }
        let html = buildHTML(symbols: symbols, dark: darkTheme)
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: base)
    }

    private func buildHTML(symbols: [String], dark: Bool) -> String {
        let cleaned = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let items = cleaned.map { sym -> String in
            // For funds or CN symbols, user should provide proper TradingView symbol format, we pass as-is
            return "{\"description\": \"\", \"proName\": \"\(sym)\"}"
        }.joined(separator: ",\n            ")

        let colorTheme = dark ? "dark" : "light"
        let css = """
        html, body, .tradingview-widget-container { background: transparent !important; }
        * { background-color: transparent !important; }
        """

        // TradingView Ticker Tape embed
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
            <style>\(css)</style>
        </head>
        <body>
            <div class=\"tradingview-widget-container\" style=\"background: transparent;\">
                <div class=\"tradingview-widget-container__widget\"></div>
            </div>
            <script type=\"text/javascript\" src=\"https://s3.tradingview.com/external-embedding/embed-widget-ticker-tape.js\" async>
            {
                \"symbols\": [\(items)],
                \"showSymbolLogo\": true,
                \"colorTheme\": \"\(colorTheme)\",
                \"isTransparent\": true,
                \"displayMode\": \"adaptive\",
                \"locale\": \"zh_CN\"
            }
            </script>
        </body>
        </html>
        """
        return html
    }
}
