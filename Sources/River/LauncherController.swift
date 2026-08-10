import AppKit
import Foundation

private final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private final class GlowView: NSVisualEffectView {
  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(rect: bounds, transform: nil)
  }
}

private final class GlowingFieldEditor: NSTextView {
  override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    isFieldEditor = true
    insertionPointColor = NSColor(calibratedRed: 0.31, green: 0.72, blue: 1, alpha: 1)
  }

  required init?(coder: NSCoder) { nil }

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedRed: 0.16, green: 0.58, blue: 1, alpha: 0.95)
    glow.shadowBlurRadius = 7
    glow.shadowOffset = .zero
    glow.set()
    super.drawInsertionPoint(in: rect, color: insertionPointColor, turnedOn: flag)
    NSGraphicsContext.current?.restoreGraphicsState()
  }
}

private final class ResultCellView: NSTableCellView {
  let titleLabel = NSTextField(labelWithString: "")
  let subtitleLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingMiddle
    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.lineBreakMode = .byTruncatingMiddle

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
  private let fieldEditor = GlowingFieldEditor(frame: .zero, textContainer: nil)
  private let table = NSTableView()
  private let scrollView = NSScrollView()
  private var rows: [Row] = []
  private var selectedIndex = 0

  init(configStore: ConfigStore) {
    self.configStore = configStore
    panel = LauncherPanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 52),
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

  func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
    client as? NSTextField === input ? fieldEditor : nil
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

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }

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
    let visualEffect = GlowView()
    visualEffect.material = .hudWindow
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active
    visualEffect.appearance = NSAppearance(named: .darkAqua)
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 0
    visualEffect.layer?.masksToBounds = false
    visualEffect.layer?.borderWidth = 1
    visualEffect.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.62).cgColor
    visualEffect.layer?.shadowColor = NSColor.systemBlue.cgColor
    visualEffect.layer?.shadowOpacity = 0.42
    visualEffect.layer?.shadowRadius = 12
    visualEffect.layer?.shadowOffset = .zero

    input.placeholderString = nil
    input.font = .systemFont(ofSize: 22, weight: .regular)
    input.textColor = .white
    input.focusRingType = .none
    input.isBezeled = false
    input.drawsBackground = false
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

    visualEffect.addSubview(input)
    visualEffect.addSubview(scrollView)
    panel.contentView = visualEffect

    NSLayoutConstraint.activate([
      input.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
      input.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
      input.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 7),
      input.heightAnchor.constraint(equalToConstant: 38),
      scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 6),
      scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -6),
      scrollView.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 3),
      scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4),
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
    let resultsHeight = CGFloat(rowCount) * 44
    let height: CGFloat = rowCount == 0 ? 52 : min(52 + resultsHeight, 316)
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
    frame.origin.y = visible.maxY - max(90, visible.height * 0.16)
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
