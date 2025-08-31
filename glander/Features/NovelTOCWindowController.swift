import AppKit

@MainActor
final class NovelTOCWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var chapters: [MenuBarNovelReader.Chapter] = []
    private var filtered: [MenuBarNovelReader.Chapter] = []
    private let onSelect: (Int) -> Void

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let searchField = NSSearchField()

    init(chapters: [MenuBarNovelReader.Chapter], onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(window: nil)
        self.chapters = chapters
        self.filtered = chapters
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateChapters(_ chapters: [MenuBarNovelReader.Chapter]) {
        self.chapters = chapters
        applyFilter(searchField.stringValue)
    }

    private func setupUI() {
        let contentRect = NSRect(x: 0, y: 0, width: 560, height: 480)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable]
        let win = NSWindow(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        win.title = "目录"
        win.isReleasedWhenClosed = false

        let container = NSView(frame: contentRect)
        container.autoresizingMask = [.width, .height]

        searchField.frame = NSRect(x: 12, y: contentRect.height - 40, width: contentRect.width - 24, height: 24)
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = "搜索章节标题…"
        searchField.delegate = self

        scroll.frame = NSRect(x: 12, y: 12, width: contentRect.width - 24, height: contentRect.height - 60)
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col.title = "章节"
        col.width = scroll.frame.width - 4

        table.addTableColumn(col)
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.autoresizingMask = [.width, .height]

        scroll.documentView = table

        container.addSubview(searchField)
        container.addSubview(scroll)
        win.contentView = container
        self.window = win
    }

    // MARK: - Actions
    @objc private func doubleClicked() {
        let row = table.clickedRow
        guard row >= 0, row < filtered.count else { return }
        onSelect(filtered[row].charOffset)
        self.close()
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let text: String = filtered[row].title
        if let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        let tf = NSTextField(labelWithString: text)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.usesSingleLineMode = true
        let cell = NSTableCellView()
        cell.identifier = id
        cell.textField = tf
        tf.frame = NSRect(x: 8, y: 2, width: tableView.bounds.width - 16, height: 20)
        tf.autoresizingMask = [.width]
        cell.addSubview(tf)
        return cell
    }

    // MARK: - Search
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ term: String) {
        if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = chapters
        } else {
            let q = term.lowercased()
            filtered = chapters.filter { $0.title.lowercased().contains(q) }
        }
        table.reloadData()
        if !filtered.isEmpty { table.scrollRowToVisible(0) }
    }
}
