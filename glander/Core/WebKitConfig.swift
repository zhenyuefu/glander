import WebKit

@MainActor
enum WebKitConfig {
    static let sharedPool = WKProcessPool()

    static func make(ephemeral: Bool = true) -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.processPool = sharedPool
        cfg.suppressesIncrementalRendering = false
        if ephemeral {
            cfg.websiteDataStore = .nonPersistent()
        }
        cfg.userContentController = WKUserContentController()
        return cfg
    }
}
