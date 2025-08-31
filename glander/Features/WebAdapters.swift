import WebKit

enum WebAdapter {
    case none
    case xiaohongshu
}

struct WebAdapters {
    @MainActor static func apply(_ adapter: WebAdapter, to controller: TransparentWebViewController) {
        switch adapter {
        case .none:
            break
        case .xiaohongshu:
            // Use a Safari-like UA to improve compatibility
            controller.customUserAgent = safariUA()
            // Respect user styling; do not force transparency or inject CSS here.
        }
    }

    private static func safariUA() -> String {
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }
}

// Intentionally no CSS injection here to preserve original page styling.
