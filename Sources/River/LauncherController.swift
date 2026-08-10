import AppKit
import Foundation

private final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private final class GlowView: NSView {
  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(rect: bounds, transform: nil)
  }
}

private enum RiverLayout {
  static let glowInset: CGFloat = 22
  static let surfaceWidth: CGFloat = 760
  static let barHeight: CGFloat = 76
  static let rowHeight: CGFloat = 52

  static var windowWidth: CGFloat { surfaceWidth + glowInset * 2 }
  static var restingWindowHeight: CGFloat { barHeight + glowInset * 2 }
}

private final class ResultCellView: NSTableCellView {
  let titleLabel = NSTextField(labelWithString: "")
  let subtitleLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingMiddle
    subtitleLabel.font = .systemFont(ofSize: 12)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.lineBreakMode = .byTruncatingMiddle

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }
}

final class LauncherController: NSObject, NSWindowDelegate, NSTextFieldDelegate,
  NSTableViewDataSource, NSTableViewDelegate
{
  private struct Row {
    let title: String
    let subtitle: String?
    let file: FileResult?
  }

  private let configStore: ConfigStore
  private let spotlight = SpotlightSearch()
  private let plugins = PluginRunner()
  private let lucky = LuckyResolver()
  private let panel: LauncherPanel
  private let input = NSTextField()
  private let table = NSTableView()
  private let scrollView = NSScrollView()
  private var rows: [Row] = []
  private var selectedIndex = 0

  init(configStore: ConfigStore) {
    self.configStore = configStore
    panel = LauncherPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: RiverLayout.windowWidth,
        height: RiverLayout.restingWindowHeight
      ),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    super.init()
    configureWindow()
    configureContent()
  }

  var isVisible: Bool { panel.isVisible }

  func toggle() {
    isVisible ? dismiss() : show()
  }

  func show() {
    rows = []
    selectedIndex = 0
    input.stringValue = ""
    scrollView.isHidden = true
    table.reloadData()
    resize(for: 0)
    positionOnActiveScreen()

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(input)
    if let editor = panel.fieldEditor(true, for: input) as? NSTextView {
      editor.insertionPointColor = NSColor(
        calibratedRed: 0.31, green: 0.72, blue: 1, alpha: 1)
      editor.isEditable = true
      editor.isSelectable = true
      editor.isRichText = false
      editor.drawsBackground = false
    }
  }

  func dismiss() {
    spotlight.cancel()
    plugins.cancel()
    lucky.cancel()
    panel.orderOut(nil)
    input.stringValue = ""
    rows = []
  }

  func windowDidResignKey(_ notification: Notification) {
    dismiss()
  }

  func controlTextDidChange(_ obj: Notification) {
    refresh(for: input.stringValue)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      submit()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      dismiss()
      return true
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)
      return true
    default:
      return false
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    RiverLayout.rowHeight
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let identifier = NSUserInterfaceItemIdentifier("result")
    let cell =
      (tableView.makeView(withIdentifier: identifier, owner: self) as? ResultCellView)
      ?? ResultCellView()
    cell.identifier = identifier
    cell.titleLabel.stringValue = rows[row].title
    cell.subtitleLabel.stringValue = rows[row].subtitle ?? ""
    cell.subtitleLabel.isHidden = rows[row].subtitle == nil
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if table.selectedRow >= 0 { selectedIndex = table.selectedRow }
  }

  private func configureWindow() {
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = true
    panel.delegate = self
    panel.isReleasedWhenClosed = false
  }

  private func configureContent() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.clear.cgColor

    let surface = GlowView()
    surface.appearance = NSAppearance(named: .darkAqua)
    surface.wantsLayer = true
    surface.layer?.backgroundColor =
      NSColor(
        calibratedRed: 0.012,
        green: 0.017,
        blue: 0.028,
        alpha: 0.80
      ).cgColor
    surface.layer?.cornerRadius = 0
    surface.layer?.masksToBounds = false
    surface.layer?.borderWidth = 2
    surface.layer?.borderColor =
      NSColor(
        calibratedRed: 0.12,
        green: 0.53,
        blue: 1,
        alpha: 0.96
      ).cgColor
    surface.layer?.shadowColor =
      NSColor(
        calibratedRed: 0.05,
        green: 0.45,
        blue: 1,
        alpha: 1
      ).cgColor
    surface.layer?.shadowOpacity = 0.78
    surface.layer?.shadowRadius = 18
    surface.layer?.shadowOffset = .zero
    surface.translatesAutoresizingMaskIntoConstraints = false

    input.placeholderString = nil
    input.font = .systemFont(ofSize: 28, weight: .light)
    input.textColor = .white
    input.focusRingType = .none
    input.isBezeled = false
    input.drawsBackground = false
    input.isEditable = true
    input.isSelectable = true
    input.isEnabled = true
    input.delegate = self
    input.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.backgroundColor = .clear
    table.gridStyleMask = []
    table.intercellSpacing = NSSize(width: 0, height: 0)
    table.selectionHighlightStyle = .regular
    table.delegate = self
    table.dataSource = self
    table.target = self
    table.doubleAction = #selector(doubleClickResult)

    scrollView.documentView = table
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.isHidden = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    surface.addSubview(input)
    surface.addSubview(scrollView)
    root.addSubview(surface)
    panel.contentView = root

    NSLayoutConstraint.activate([
      surface.leadingAnchor.constraint(
        equalTo: root.leadingAnchor, constant: RiverLayout.glowInset),
      surface.trailingAnchor.constraint(
        equalTo: root.trailingAnchor,
        constant: -RiverLayout.glowInset
      ),
      surface.topAnchor.constraint(equalTo: root.topAnchor, constant: RiverLayout.glowInset),
      surface.bottomAnchor.constraint(
        equalTo: root.bottomAnchor,
        constant: -RiverLayout.glowInset
      ),
      input.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 30),
      input.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -30),
      input.topAnchor.constraint(equalTo: surface.topAnchor, constant: 20),
      input.heightAnchor.constraint(equalToConstant: 44),
      scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
      scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
      scrollView.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 8),
      scrollView.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -4),
    ])
  }

  private func refresh(for rawInput: String) {
    spotlight.cancel()
    plugins.cancel()
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      setRows([])
      return
    }

    if text == "/" {
      let names = plugins.availablePlugins(in: configStore.value.pluginDirectory)
      let summary =
        names.isEmpty ? "No plugins found" : names.map { "/" + $0 }.joined(separator: "   ")
      setRows([Row(title: summary, subtitle: nil, file: nil)])
      return
    }

    if let request = PluginRequest(input: text) {
      setRows([Row(title: "Running /\(request.name)…", subtitle: nil, file: nil)])
      plugins.run(request, config: configStore.value) { [weak self] output in
        self?.setRows([Row(title: output, subtitle: nil, file: nil)])
      }
      return
    }

    if text.hasPrefix("'") {
      let query = String(text.dropFirst())
      guard !query.isEmpty else {
        setRows([Row(title: "Type a filename", subtitle: "Spotlight searches this Mac", file: nil)])
        return
      }
      setRows([Row(title: "Searching…", subtitle: nil, file: nil)])
      spotlight.search(query, limit: configStore.value.maxFileResults) { [weak self] results in
        let rows = results.map { Row(title: $0.title, subtitle: $0.subtitle, file: $0) }
        self?.setRows(
          rows.isEmpty ? [Row(title: "No files found", subtitle: nil, file: nil)] : rows)
      }
      return
    }

    if let word = definitionWord(in: text) {
      let definition = DictionaryLookup.definition(of: word) ?? "No definition found"
      setRows([Row(title: definition, subtitle: "↩ Open in Dictionary", file: nil)])
      return
    }

    setRows([])
  }

  private func setRows(_ newRows: [Row]) {
    rows = newRows
    scrollView.isHidden = rows.isEmpty
    selectedIndex = 0
    table.reloadData()
    if rows.first?.file != nil {
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    resize(for: rows.count)
  }

  private func resize(for rowCount: Int) {
    let oldTop = panel.frame.maxY
    let resultsHeight = CGFloat(rowCount) * RiverLayout.rowHeight
    let surfaceHeight = min(RiverLayout.barHeight + resultsHeight, 336)
    let height = surfaceHeight + RiverLayout.glowInset * 2
    var frame = panel.frame
    frame.size.height = height
    frame.origin.y = oldTop - height
    panel.setFrame(frame, display: true, animate: false)
  }

  private func positionOnActiveScreen() {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    var frame = panel.frame
    frame.origin.x = visible.midX - frame.width / 2
    let targetCenterY = visible.minY + visible.height * 0.62
    frame.origin.y = targetCenterY - frame.height / 2
    panel.setFrame(frame, display: false)
  }

  private func moveSelection(by offset: Int) {
    let fileRows = rows.indices.filter { rows[$0].file != nil }
    guard !fileRows.isEmpty else { return }
    let currentPosition = fileRows.firstIndex(of: selectedIndex) ?? 0
    let nextPosition = max(0, min(fileRows.count - 1, currentPosition + offset))
    selectedIndex = fileRows[nextPosition]
    table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
    table.scrollRowToVisible(selectedIndex)
  }

  private func submit() {
    let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    if text.hasPrefix("'"), rows.indices.contains(selectedIndex),
      let file = rows[selectedIndex].file
    {
      NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
      dismiss()
      return
    }

    if let word = definitionWord(in: text),
      let url = URL(
        string: "dict://"
          + (word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word))
    {
      NSWorkspace.shared.open(url)
      dismiss()
      return
    }

    if text.hasPrefix("/") { return }

    let luckyPrefix = "lk "
    if text.lowercased().hasPrefix(luckyPrefix) {
      let query = String(text.dropFirst(luckyPrefix.count))
      guard !query.isEmpty,
        let luckyURL = URLBuilder.searchURL(template: configStore.value.luckyURL, query: query),
        let fallbackURL = URLBuilder.searchURL(template: configStore.value.searchURL, query: query)
      else {
        return
      }
      setRows([Row(title: "Finding the lucky result…", subtitle: nil, file: nil)])
      lucky.resolve(luckyURL, fallbackURL: fallbackURL) { [weak self] resolvedURL in
        guard let self else { return }
        Browser.open(resolvedURL, application: self.configStore.value.browser)
        self.dismiss()
      }
      return
    }

    guard let url = URLBuilder.searchURL(template: configStore.value.searchURL, query: text) else {
      return
    }
    Browser.open(url, application: configStore.value.browser)
    dismiss()
  }

  @objc private func doubleClickResult() {
    guard table.clickedRow >= 0 else { return }
    selectedIndex = table.clickedRow
    submit()
  }

  private func definitionWord(in text: String) -> String? {
    let prefix = "define "
    guard text.lowercased().hasPrefix(prefix) else { return nil }
    let word = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return word.isEmpty ? nil : word
  }
}
