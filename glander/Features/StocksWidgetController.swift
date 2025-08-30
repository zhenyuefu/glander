import AppKit
import WebKit

enum StocksWidgetStyle: String {
    case ticker      // scrolling tape
    case overview    // watchlist with mini charts
    case single      // single symbol overview
}

final class StocksWidgetController: NSViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    var symbols: [String] = [] { didSet { reload() } }
    var darkTheme: Bool = true { didSet { reload() } }
    var style: StocksWidgetStyle = .ticker { didSet { reload() } }

    // Recommended minimal content size per widget style
    var recommendedMinSize: NSSize {
        switch style {
        case .ticker:
            return NSSize(width: 600, height: 56)
        case .overview:
            return NSSize(width: 800, height: 380)
        case .single:
            return NSSize(width: 800, height: 320)
        }
    }

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
        // Provide a non-zero default preferred size to avoid collapsing
        if self.preferredContentSize == .zero {
            self.preferredContentSize = recommendedMinSize
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        webView.frame = view.bounds
    }

    func reload() {
        guard isViewLoaded else { return }
        let html = buildHTML(symbols: symbols, dark: darkTheme, style: style)
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: base)
    }

    private func buildHTML(symbols: [String], dark: Bool, style: StocksWidgetStyle) -> String {
        let cleaned = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let colorTheme = dark ? "dark" : "light"
        switch style {
        case .ticker:
            let css = """
            html, body, .tradingview-widget-container { background: transparent !important; }
            * { background-color: transparent !important; }
            html, body { margin: 0; padding: 0; }
            """
            let items = cleaned.map { sym -> String in
                return "{\"description\": \"\", \"proName\": \"\(sym)\"}"
            }.joined(separator: ",\n            ")
            return """
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

        case .overview:
            let css = """
            html, body, .tradingview-widget-container { background: transparent !important; }
            * { background-color: transparent !important; }
            html, body { margin: 0; padding: 0; height: 100%; }
            /* Fill the viewport so widget is fully visible */
            .tradingview-widget-container, .tradingview-widget-container__widget { height: 100vh; }
            """
            // Market Overview: a watchlist with mini charts
            let items = cleaned.map { sym -> String in
                return "{\"s\": \"\(sym)\", \"d\": \"\(sym)\"}"
            }.joined(separator: ",\n                    ")
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset=\"utf-8\">
                <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
                <style>\(css)</style>
            </head>
            <body>
                <div class=\"tradingview-widget-container\">
                    <div class=\"tradingview-widget-container__widget\"></div>
                </div>
                <script type=\"text/javascript\" src=\"https://s3.tradingview.com/external-embedding/embed-widget-market-overview.js\" async>
                {
                  \"colorTheme\": \"\(colorTheme)\",
                  \"dateRange\": \"1D\",
                  \"showChart\": true,
                  \"locale\": \"zh_CN\",
                  \"isTransparent\": true,
                  \"width\": \"100%\",
                  \"height\": \"100%\",
                  \"tabs\": [
                    {
                      \"title\": \"自选\",
                      \"symbols\": [\n                    \(items)\n                      ]
                    }
                  ]
                }
                </script>
            </body>
            </html>
            """

        case .single:
            let css = """
            html, body, .tradingview-widget-container { background: transparent !important; }
            * { background-color: transparent !important; }
            html, body { margin: 0; padding: 0; height: 100%; }
            /* Fill the viewport so widget is fully visible */
            .tradingview-widget-container, .tradingview-widget-container__widget { height: 100vh; }
            """
            // Single symbol overview: take first symbol or fallback to AAPL
            let sym = cleaned.first ?? "NASDAQ:AAPL"
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset=\"utf-8\">
                <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
                <style>\(css)</style>
            </head>
            <body>
                <div class=\"tradingview-widget-container\">
                    <div class=\"tradingview-widget-container__widget\"></div>
                </div>
                <script type=\"text/javascript\" src=\"https://s3.tradingview.com/external-embedding/embed-widget-symbol-overview.js\" async>
                {
                  \"symbols\": [[\"\(sym)|1D\"]],
                  \"chartOnly\": false,
                  \"width\": \"100%\",
                  \"height\": \"100%\",
                  \"locale\": \"zh_CN\",
                  \"colorTheme\": \"\(colorTheme)\",
                  \"isTransparent\": true
                }
                </script>
            </body>
            </html>
            """
        }
    }
}
