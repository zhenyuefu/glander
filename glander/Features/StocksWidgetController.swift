import AppKit
import WebKit

enum StocksWidgetStyle: String {
    case ticker      // scrolling tape
    case overview    // watchlist with mini charts
    case single      // single symbol overview
}

@MainActor
final class StocksWidgetController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    var symbols: [String] = [] { didSet { reload() } }
    var darkTheme: Bool = true { didSet { reload() } }
    var style: StocksWidgetStyle = .ticker {
        didSet {
            let changed = oldValue != style
            reload()
            if changed { DispatchQueue.main.async { [weak self] in self?.applyRecommendedWindowSizing() } }
        }
    }

    // Recommended minimal content size per widget style
    var recommendedMinSize: NSSize {
        switch style {
        case .ticker:
            // Slightly taller to avoid bottom clipping of the tape
            return NSSize(width: 600, height: 64)
        case .overview:
            return NSSize(width: 800, height: 380)
        case .single:
            return NSSize(width: 800, height: 320)
        }
    }

    override func loadView() {
        let cfg = WebKitConfig.make(ephemeral: Preferences.shared.useEphemeralWebSession)
        // Observe page height changes and report back for window auto-sizing
        cfg.userContentController.add(self, name: "stocksWidget")
        cfg.userContentController.addUserScript(WKUserScript(source: Self.resizeObserverJS,
                                                             injectionTime: .atDocumentEnd,
                                                             forMainFrameOnly: true))
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
        // Set a reasonable preferred size to avoid collapsing
        self.preferredContentSize = recommendedMinSize
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        webView.frame = view.bounds
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Ensure the window adopts the recommended size on first show
        applyRecommendedWindowSizing()
    }

    // Note: Avoid referencing actor-isolated properties in deinit; cleanup is handled by WebKit.

    func reload() {
        guard isViewLoaded else { return }
        webView.stopLoading()
        let html = buildHTML(symbols: symbols, dark: darkTheme, style: style)
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: base)
    }

    private func buildHTML(symbols: [String], dark: Bool, style: StocksWidgetStyle) -> String {
        let cleaned = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let colorTheme = dark ? "dark" : "light"
        let recommendedHeight: Int = {
            switch style {
            case .ticker: return 56
            case .overview: return 380
            case .single: return 320
            }
        }()
        switch style {
        case .ticker:
            let css = """
            html, body, .tradingview-widget-container { background: transparent !important; }
            * { background-color: transparent !important; }
            html, body { margin: 0; padding: 0; overflow: hidden; }
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
            html, body { margin: 0; padding: 0; overflow: hidden; }
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
                  \"height\": \(recommendedHeight),
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
            html, body { margin: 0; padding: 0; overflow: hidden; }
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
                  \"height\": \(recommendedHeight),
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

// MARK: - Window sizing helpers
private extension StocksWidgetController {
    func applyRecommendedWindowSizing() {
        // Keep VC hints in sync
        self.preferredContentSize = recommendedMinSize
        guard let win = view.window else { return }
        // Enforce a sensible minimum and set content size to match the style
        win.contentMinSize = recommendedMinSize
        // Resize content area to the recommended size while preserving position as much as possible
        win.setContentSize(recommendedMinSize)
    }
}

// MARK: - WKScriptMessageHandler
extension StocksWidgetController {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "stocksWidget" else { return }
        if let dict = message.body as? [String: Any], let h = dict["height"] as? CGFloat {
            applyMeasuredContentHeight(h)
        } else if let h = message.body as? CGFloat {
            applyMeasuredContentHeight(h)
        } else if let n = message.body as? NSNumber {
            applyMeasuredContentHeight(CGFloat(truncating: n))
        }
    }

    private func applyMeasuredContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard let win = view.window else { return }
        let width = max(webView.bounds.width.rounded(.up), recommendedMinSize.width)
        // Add a small fudge for ticker to avoid bottom clipping on some scales
        let fudge: CGFloat = (style == .ticker) ? 8 : 0
        let clampedH = max(height.rounded(.up) + fudge, recommendedMinSize.height)
        win.contentMinSize = recommendedMinSize
        win.setContentSize(NSSize(width: width, height: clampedH))
    }
}

// MARK: - JS helpers
private extension StocksWidgetController {
    // Observe the main container height and notify native to resize window.
    static let resizeObserverJS: String = {
        return """
        (function(){
          function post(h){
            try { window.webkit.messageHandlers.stocksWidget.postMessage({height: Math.ceil(h)}); } catch(e) {}
          }
          function measure(){
            var root = document.querySelector('.tradingview-widget-container') || document.body;
            if (!root) return;
            var rect = root.getBoundingClientRect();
            var h = rect && rect.height ? rect.height : document.documentElement.scrollHeight || document.body.scrollHeight || 0;
            if (h > 0) { post(h); }
          }
          // Initial attempts: now + a few retries to catch async embed
          measure();
          setTimeout(measure, 120);
          setTimeout(measure, 300);
          setTimeout(measure, 600);
          // Observe subsequent size changes
          if (typeof ResizeObserver !== 'undefined'){
            try {
              var root = document.querySelector('.tradingview-widget-container') || document.body;
              if (root) ro.observe(root);
              // Clean up observer on page unload to prevent memory leaks
              window.addEventListener('unload', function() { ro.disconnect(); }, { once: true });
            } catch(e) {}
          } else {
            // Fallback polling for a short period
            var t = 0; var id = setInterval(function(){ measure(); if (++t > 12) clearInterval(id); }, 250);
          }
          // Prevent scrollbars for better visual fit while native resizes
          try { document.documentElement.style.overflow = 'hidden'; document.body.style.overflow = 'hidden'; } catch(e){}
        })();
        """
    }()
}
