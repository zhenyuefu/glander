import AppKit
import PDFKit

final class PDFViewerController: NSViewController {
    private let pdfView = PDFView()
    private var timer: DispatchSourceTimer?
    var autoScrollEnabled: Bool = false { didSet { autoScrollEnabled ? startAutoScroll() : stopAutoScroll() } }
    // points per second
    var autoScrollSpeed: Double = 40.0 { didSet { restartTimerIfNeeded() } }

    override func loadView() {
        let container = NSView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        container.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.view = container
        // Provide a sensible default so the window won't shrink to 0x0
        if self.preferredContentSize == .zero {
            self.preferredContentSize = NSSize(width: 900, height: 600)
        }
    }

    func open(url: URL) {
        pdfView.document = PDFDocument(url: url)
    }

    private func startAutoScroll() {
        stopAutoScroll()
        guard autoScrollEnabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0/60.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func stopAutoScroll() {
        timer?.cancel()
        timer = nil
    }

    private func restartTimerIfNeeded() {
        if autoScrollEnabled { startAutoScroll() }
    }

    private func tick() {
        guard autoScrollEnabled, let scrollView = pdfView.enclosingScrollView else { return }
        let contentView = scrollView.contentView
        var origin = contentView.bounds.origin
        origin.y += CGFloat(autoScrollSpeed / 60.0)
        let maxY = (scrollView.documentView?.bounds.height ?? 0) - contentView.bounds.height
        if origin.y >= maxY - 1 {
            // loop to top
            origin.y = 0
        }
        contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(contentView)
    }
}
