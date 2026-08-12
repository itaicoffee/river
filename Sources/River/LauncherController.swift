import AppKit
import Foundation

private final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)
    if modifiers == .command,
      event.charactersIgnoringModifiers?.lowercased() == "a",
      let editor = firstResponder as? NSTextView
    {
      editor.selectAll(nil)
      return true
    }

    if modifiers == .command,
      event.charactersIgnoringModifiers?.lowercased() == "v",
      let editor = firstResponder as? NSTextView
    {
      editor.paste(nil)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}

private final class GlowView: NSView {
  private let gradient = CAGradientLayer()
  private var isThinking = false

  private let restingBorderColor = NSColor(
    calibratedRed: 0.28,
    green: 0.55,
    blue: 0.82,
    alpha: 0.44
  ).cgColor

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    gradient.colors = [
      NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.125, alpha: 0.98).cgColor,
      NSColor(calibratedRed: 0.025, green: 0.032, blue: 0.050, alpha: 0.98).cgColor,
    ]
    gradient.startPoint = CGPoint(x: 0.08, y: 1)
    gradient.endPoint = CGPoint(x: 0.92, y: 0)
    layer?.insertSublayer(gradient, at: 0)
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()

    // The launcher changes height as its result mode changes. Keep the backing
    // layers in lockstep with the view so Core Animation does not interpolate
    // from the previous mode's geometry and briefly expose stale pixels.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradient.frame = bounds
    gradient.cornerRadius = RiverLayout.cornerRadius
    layer?.shadowPath = CGPath(
      roundedRect: bounds,
      cornerWidth: RiverLayout.cornerRadius,
      cornerHeight: RiverLayout.cornerRadius,
      transform: nil
    )
    CATransaction.commit()
  }

  func startThinking() {
    guard !isThinking, let layer else { return }
    isThinking = true

    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.borderColor = NSColor(
        calibratedRed: 0.34,
        green: 0.72,
        blue: 1,
        alpha: 0.72
      ).cgColor
      layer.shadowOpacity = 0.72
      CATransaction.commit()
      return
    }

    let timing = CAMediaTimingFunction(name: .easeInEaseOut)
    let opacity = CAKeyframeAnimation(keyPath: "shadowOpacity")
    opacity.values = [0.38, 0.82, 0.38]
    opacity.keyTimes = [0, 0.5, 1]
    opacity.timingFunctions = [timing, timing]
    opacity.duration = 1.4
    opacity.repeatCount = .infinity

    let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
    radius.values = [20, 32, 20]
    radius.keyTimes = [0, 0.5, 1]
    radius.timingFunctions = [timing, timing]
    radius.duration = 1.4
    radius.repeatCount = .infinity

    let border = CAKeyframeAnimation(keyPath: "borderColor")
    border.values = [
      restingBorderColor,
      NSColor(calibratedRed: 0.34, green: 0.72, blue: 1, alpha: 0.8).cgColor,
      restingBorderColor,
    ]
    border.keyTimes = [0, 0.5, 1]
    border.timingFunctions = [timing, timing]
    border.duration = 1.4
    border.repeatCount = .infinity

    layer.add(opacity, forKey: "river.thinking.opacity")
    layer.add(radius, forKey: "river.thinking.radius")
    layer.add(border, forKey: "river.thinking.border")
  }

  func stopThinking() {
    guard let layer else { return }
    isThinking = false
    layer.removeAnimation(forKey: "river.thinking.opacity")
    layer.removeAnimation(forKey: "river.thinking.radius")
    layer.removeAnimation(forKey: "river.thinking.border")

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.borderColor = restingBorderColor
    layer.shadowOpacity = 0.46
    layer.shadowRadius = 24
    CATransaction.commit()
  }
}

private enum RiverLayout {
  // Leave enough transparent window area for the largest animated shadow to
  // decay completely. A tight inset clips the blur at the panel boundary and
  // reveals that boundary as a faint rectangle around the glow.
  static let glowInset: CGFloat = 72
  static let surfaceWidth: CGFloat = 700
  static let inputAreaHeight: CGFloat = 78
  static let inputPadding: CGFloat = 24
  static let rowHeight: CGFloat = 58
  static let resultsTopInset: CGFloat = 8
  static let resultsBottomInset: CGFloat = 10
  static let resultsClipAllowance: CGFloat = 1
  static let dividerHeight: CGFloat = 1
  static let cornerRadius: CGFloat = 18
  static let statusGap: CGFloat = 12
  static let statusSurfaceHeight: CGFloat = 54
  static let statusHorizontalPadding: CGFloat = 14
  static let maximumVisibleRows = 5

  static var windowWidth: CGFloat { surfaceWidth + glowInset * 2 }
  static var restingWindowHeight: CGFloat { inputAreaHeight + glowInset * 2 }

  static func surfaceHeight(for rowCount: Int) -> CGFloat {
    guard rowCount > 0 else { return inputAreaHeight }
    let visibleRows = min(rowCount, maximumVisibleRows)
    return inputAreaHeight + dividerHeight + resultsTopInset + resultsBottomInset
      + CGFloat(visibleRows) * rowHeight + resultsClipAllowance
  }
}

private final class ResultCellView: NSTableCellView {
  private let resultIcon = NSImageView()
  private let resultEmoji = NSTextField(labelWithString: "")
  let titleLabel = NSTextField(labelWithString: "")
  let subtitleLabel = NSTextField(labelWithString: "")
  private let actionLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    resultIcon.imageScaling = .scaleProportionallyUpOrDown
    resultIcon.translatesAutoresizingMaskIntoConstraints = false

    resultEmoji.font = NSFont(name: "Apple Color Emoji", size: 24)
      ?? .systemFont(ofSize: 24)
    resultEmoji.alignment = .center
    resultEmoji.maximumNumberOfLines = 1
    resultEmoji.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
    titleLabel.lineBreakMode = .byTruncatingMiddle
    titleLabel.maximumNumberOfLines = 1

    subtitleLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
    subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.48)
    subtitleLabel.lineBreakMode = .byTruncatingMiddle
    subtitleLabel.maximumNumberOfLines = 1

    actionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    actionLabel.textColor = NSColor.white.withAlphaComponent(0.42)
    actionLabel.alignment = .right
    actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    actionLabel.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 1
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(resultIcon)
    addSubview(resultEmoji)
    addSubview(stack)
    addSubview(actionLabel)
    NSLayoutConstraint.activate([
      resultIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      resultIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
      resultIcon.widthAnchor.constraint(equalToConstant: 30),
      resultIcon.heightAnchor.constraint(equalToConstant: 30),
      resultEmoji.leadingAnchor.constraint(equalTo: resultIcon.leadingAnchor),
      resultEmoji.trailingAnchor.constraint(equalTo: resultIcon.trailingAnchor),
      resultEmoji.centerYAnchor.constraint(equalTo: resultIcon.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: resultIcon.trailingAnchor, constant: 12),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: actionLabel.leadingAnchor, constant: -14),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      actionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
      actionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }

  func configure(
    title: String,
    subtitle: String?,
    icon: NSImage?,
    emoji: String? = nil,
    action: String?
  ) {
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle ?? ""
    subtitleLabel.isHidden = subtitle == nil
    resultIcon.image = icon
    resultIcon.isHidden = emoji != nil
    resultIcon.contentTintColor = icon?.isTemplate == true
      ? NSColor(calibratedRed: 0.38, green: 0.72, blue: 1, alpha: 0.9)
      : nil
    resultEmoji.stringValue = emoji ?? ""
    resultEmoji.isHidden = emoji == nil
    actionLabel.stringValue = action.map { "\($0)   ↵" } ?? ""
    actionLabel.isHidden = action == nil
  }
}

private final class ResultRowView: NSTableRowView {
  private var isHovered = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 11
    if #available(macOS 10.15, *) { layer?.cornerCurve = .continuous }
  }

  required init?(coder: NSCoder) { nil }

  override func updateTrackingAreas() {
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .activeInKeyWindow],
        owner: self,
        userInfo: nil
      ))
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateAppearance()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateAppearance()
  }

  override var isSelected: Bool {
    didSet { updateAppearance() }
  }

  override func drawSelection(in dirtyRect: NSRect) {}

  private func updateAppearance() {
    if isSelected {
      layer?.backgroundColor = NSColor(
        calibratedRed: 0.12, green: 0.42, blue: 0.72, alpha: 0.42
      ).cgColor
      layer?.borderWidth = 1
      layer?.borderColor = NSColor(
        calibratedRed: 0.34, green: 0.68, blue: 1, alpha: 0.32
      ).cgColor
    } else {
      layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.065 : 0).cgColor
      layer?.borderWidth = 0
    }
  }
}

final class LauncherController: NSObject, NSWindowDelegate, NSTextFieldDelegate,
  NSTableViewDataSource, NSTableViewDelegate
{
  private struct Row {
    enum Target {
      case file(FileResult)
      case application(ApplicationResult)
      case calculation(CalculationResult)
      case quicklink(QuicklinkRequest)
      case pluginSuggestion(String)
      case commandCenter(CommandCenterItem)
      case stock(StockQuote)
      case emoji(EmojiResult)
    }

    let title: String
    let subtitle: String?
    let symbolName: String
    let action: String?
    let target: Target?

    init(
      title: String,
      subtitle: String? = nil,
      symbolName: String = "sparkle",
      action: String? = nil,
      target: Target? = nil
    ) {
      self.title = title
      self.subtitle = subtitle
      self.symbolName = symbolName
      self.action = action
      self.target = target
    }
  }

  private let configStore: ConfigStore
  private let statusPlugins: StatusPluginManager
  private let spotlight = SpotlightSearch()
  private let plugins = PluginRunner()
  private let lucky = LuckyResolver()
  private let stocks = StockLookup()
  private let applicationCatalog = ApplicationCatalog()
  private let knowledge: ResultKnowledge
  private let panel: LauncherPanel
  private let surface = GlowView()
  private let statusSurface = GlowView()
  private let statusStack = NSStackView()
  private let input = NSTextField()
  private let table = NSTableView()
  private let scrollView = NSScrollView()
  private let divider = NSView()
  private let fileIconCache = NSCache<NSString, NSImage>()
  private var resultsVerticalConstraints: [NSLayoutConstraint] = []
  private var statusVerticalConstraints: [NSLayoutConstraint] = []
  private var mainSurfaceBottomConstraint: NSLayoutConstraint!
  private var rows: [Row] = []
  private var statusSnapshots: [StatusPluginSnapshot] = []
  private var cachedPluginDirectory: String?
  private var cachedPluginNames: [String]?
  private var selectedIndex = 0
  private var selectionWasExplicit = false
  private var updatingSelection = false
  private var luckyStatusWorkItem: DispatchWorkItem?

  init(
    configStore: ConfigStore,
    statusPlugins: StatusPluginManager,
    knowledge: ResultKnowledge = ResultKnowledge()
  ) {
    self.configStore = configStore
    self.statusPlugins = statusPlugins
    self.knowledge = knowledge
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
    fileIconCache.countLimit = 100
    configureWindow()
    configureContent()
    statusPlugins.onChange = { [weak self] snapshots in
      self?.setStatusPlugins(snapshots)
    }
    setStatusPlugins(statusPlugins.snapshots)
  }

  var isVisible: Bool { panel.isVisible }

  func toggle() {
    isVisible ? dismiss() : show()
  }

  func show() {
    stopLuckyPresentation()
    setStatusPlugins(statusPlugins.snapshots)
    rows = []
    selectedIndex = 0
    cachedPluginDirectory = nil
    cachedPluginNames = nil
    input.stringValue = ""
    setResultsVisible(false)
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
    stocks.cancel()
    stopLuckyPresentation()
    panel.orderOut(nil)
    input.stringValue = ""
    rows = []
    setResultsVisible(false)
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
      if isControlC(NSApp.currentEvent) {
        clearInput(textView)
        return true
      }
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

  private func isControlC(_ event: NSEvent?) -> Bool {
    guard let event else { return false }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return modifiers.contains(.control)
      && !modifiers.contains(.command)
      && event.charactersIgnoringModifiers?.lowercased() == "c"
  }

  private func clearInput(_ textView: NSTextView) {
    textView.string = ""
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    input.stringValue = ""
    refresh(for: "")
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
    let item = rows[row]
    cell.configure(
      title: item.title,
      subtitle: item.subtitle,
      icon: icon(for: item),
      emoji: emoji(for: item),
      action: item.action
    )
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    ResultRowView()
  }

  private func icon(for row: Row) -> NSImage? {
    switch row.target {
    case .application(let application):
      return fileIcon(at: application.url.path, size: NSSize(width: 30, height: 30))
    case .file(let file):
      return fileIcon(at: file.path, size: NSSize(width: 28, height: 28))
    default:
      return NSImage(systemSymbolName: row.symbolName, accessibilityDescription: nil)
    }
  }

  private func emoji(for row: Row) -> String? {
    guard case .emoji(let result)? = row.target else { return nil }
    return result.emoji
  }

  private func fileIcon(at path: String, size: NSSize) -> NSImage {
    let key = "\(Int(size.width)):\(path)" as NSString
    if let icon = fileIconCache.object(forKey: key) { return icon }

    let workspaceIcon = NSWorkspace.shared.icon(forFile: path)
    let icon = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
    icon.size = size
    fileIconCache.setObject(icon, forKey: key)
    return icon
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if table.selectedRow >= 0 {
      selectedIndex = table.selectedRow
      if !updatingSelection { selectionWasExplicit = true }
    }
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

    surface.appearance = NSAppearance(named: .darkAqua)
    surface.layer?.cornerRadius = RiverLayout.cornerRadius
    if #available(macOS 10.15, *) { surface.layer?.cornerCurve = .continuous }
    surface.layer?.masksToBounds = false
    surface.layer?.borderWidth = 1
    surface.layer?.borderColor =
      NSColor(
        calibratedRed: 0.28,
        green: 0.55,
        blue: 0.82,
        alpha: 0.44
      ).cgColor
    surface.layer?.shadowColor =
      NSColor(
        calibratedRed: 0.02,
        green: 0.25,
        blue: 0.55,
        alpha: 1
      ).cgColor
    surface.layer?.shadowOpacity = 0.46
    surface.layer?.shadowRadius = 24
    surface.layer?.shadowOffset = CGSize(width: 0, height: -6)
    surface.translatesAutoresizingMaskIntoConstraints = false

    statusSurface.appearance = NSAppearance(named: .darkAqua)
    statusSurface.layer?.cornerRadius = RiverLayout.cornerRadius
    if #available(macOS 10.15, *) { statusSurface.layer?.cornerCurve = .continuous }
    statusSurface.layer?.masksToBounds = false
    statusSurface.layer?.borderWidth = 1
    statusSurface.layer?.borderColor = NSColor(
      calibratedRed: 0.28,
      green: 0.55,
      blue: 0.82,
      alpha: 0.34
    ).cgColor
    statusSurface.layer?.shadowColor = NSColor(
      calibratedRed: 0.02,
      green: 0.25,
      blue: 0.55,
      alpha: 1
    ).cgColor
    statusSurface.layer?.shadowOpacity = 0.32
    statusSurface.layer?.shadowRadius = 18
    statusSurface.layer?.shadowOffset = CGSize(width: 0, height: -4)
    statusSurface.isHidden = true
    statusSurface.translatesAutoresizingMaskIntoConstraints = false

    statusStack.orientation = .horizontal
    statusStack.alignment = .centerY
    statusStack.distribution = .fillEqually
    statusStack.spacing = 0
    statusStack.translatesAutoresizingMaskIntoConstraints = false
    statusSurface.addSubview(statusStack)

    input.placeholderString = nil
    input.font = .systemFont(ofSize: 24, weight: .regular)
    input.textColor = NSColor.white.withAlphaComponent(0.96)
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
    table.style = .plain
    table.selectionHighlightStyle = .none
    table.rowSizeStyle = .custom
    table.delegate = self
    table.dataSource = self
    table.target = self
    table.doubleAction = #selector(doubleClickResult)

    scrollView.documentView = table
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.verticalScrollElasticity = .none
    scrollView.isHidden = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
    divider.isHidden = true
    divider.translatesAutoresizingMaskIntoConstraints = false

    surface.addSubview(input)
    surface.addSubview(divider)
    surface.addSubview(scrollView)
    root.addSubview(surface)
    root.addSubview(statusSurface)
    panel.contentView = root

    resultsVerticalConstraints = [
      scrollView.topAnchor.constraint(
        equalTo: divider.bottomAnchor, constant: RiverLayout.resultsTopInset),
      scrollView.bottomAnchor.constraint(
        equalTo: surface.bottomAnchor, constant: -RiverLayout.resultsBottomInset),
    ]
    mainSurfaceBottomConstraint = surface.bottomAnchor.constraint(
      equalTo: root.bottomAnchor,
      constant: -RiverLayout.glowInset
    )
    statusVerticalConstraints = [
      statusSurface.topAnchor.constraint(
        equalTo: surface.bottomAnchor,
        constant: RiverLayout.statusGap
      ),
      statusSurface.bottomAnchor.constraint(
        equalTo: root.bottomAnchor,
        constant: -RiverLayout.glowInset
      ),
    ]

    NSLayoutConstraint.activate([
      surface.leadingAnchor.constraint(
        equalTo: root.leadingAnchor, constant: RiverLayout.glowInset),
      surface.trailingAnchor.constraint(
        equalTo: root.trailingAnchor,
        constant: -RiverLayout.glowInset
      ),
      surface.topAnchor.constraint(equalTo: root.topAnchor, constant: RiverLayout.glowInset),
      mainSurfaceBottomConstraint,
      statusSurface.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      statusSurface.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      statusSurface.heightAnchor.constraint(equalToConstant: RiverLayout.statusSurfaceHeight),
      statusStack.leadingAnchor.constraint(
        equalTo: statusSurface.leadingAnchor,
        constant: RiverLayout.statusHorizontalPadding
      ),
      statusStack.trailingAnchor.constraint(
        equalTo: statusSurface.trailingAnchor,
        constant: -RiverLayout.statusHorizontalPadding
      ),
      statusStack.topAnchor.constraint(equalTo: statusSurface.topAnchor),
      statusStack.bottomAnchor.constraint(equalTo: statusSurface.bottomAnchor),
      input.leadingAnchor.constraint(
        equalTo: surface.leadingAnchor, constant: RiverLayout.inputPadding),
      input.trailingAnchor.constraint(
        equalTo: surface.trailingAnchor, constant: -RiverLayout.inputPadding),
      input.topAnchor.constraint(
        equalTo: surface.topAnchor, constant: RiverLayout.inputPadding),
      input.bottomAnchor.constraint(
        equalTo: divider.topAnchor, constant: -RiverLayout.inputPadding),
      divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
      divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
      divider.topAnchor.constraint(
        equalTo: surface.topAnchor, constant: RiverLayout.inputAreaHeight),
      divider.heightAnchor.constraint(equalToConstant: RiverLayout.dividerHeight),
      scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
      scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -10),
    ])
  }

  private func refresh(for rawInput: String) {
    spotlight.cancel()
    plugins.cancel()
    lucky.cancel()
    stocks.cancel()
    stopLuckyPresentation()
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      setRows([])
      return
    }

    if text.hasPrefix(">") {
      refreshCommandCenter(text)
      return
    }

    if let prompt = incompleteInputPrompt(for: rawInput) {
      setRows([prompt])
      return
    }

    if let command = RiverCommand(input: text) {
      switch command {
      case .restart:
        setRows([
          Row(
            title: "Restart River",
            subtitle: "Reload the launcher and its configuration",
            symbolName: "arrow.clockwise",
            action: "Restart"
          )
        ])
      case .settings:
        setRows([
          Row(
            title: "Open River settings",
            subtitle: "Terminal · nvim · \(displayPath(configStore.path))",
            symbolName: "slider.horizontal.3",
            action: "Open"
          )
        ])
      }
      return
    }

    if text.hasPrefix("/") {
      refreshPluginCommand(text)
      return
    }

    if text.hasPrefix("'") {
      let query = String(text.dropFirst())
      guard !query.isEmpty else {
        setRows([
          Row(
            title: "Type a filename",
            subtitle: "Spotlight searches this Mac",
            symbolName: "doc.text.magnifyingglass"
          )
        ])
        return
      }
      setRows([Row(title: "Searching…", symbolName: "magnifyingglass")])
      let resultLimit = configStore.value.maxFileResults
      let candidateLimit = max(50, resultLimit * 10)
      spotlight.search(query, limit: candidateLimit) { [weak self] results in
        guard let self else { return }
        let learnedOrder = self.knowledge.ordered(
          results, for: query, itemIdentifier: \.knowledgeIdentifier)
        let ordered = FileResult.directoriesFirst(learnedOrder)
        let visibleResults = ordered.prefix(resultLimit)
        let rows = visibleResults.map {
          Row(
            title: $0.title,
            subtitle: $0.subtitle,
            symbolName: $0.isDirectory ? "folder" : "doc",
            action: "Open",
            target: .file($0)
          )
        }
        self.setRows(
          rows.isEmpty
            ? [Row(title: "No files found", symbolName: "doc.text.magnifyingglass")] : rows,
          selectFirst: !rows.isEmpty
        )
      }
      return
    }

    if let request = EmojiRequest(input: text) {
      let matches = EmojiCatalog.matches(request.query)
      let emojiRows = matches.map { result in
        Row(
          title: result.name,
          subtitle: "Emoji",
          action: "Copy",
          target: .emoji(result)
        )
      }
      setRows(
        emojiRows.isEmpty
          ? [
            Row(
              title: "No emoji matching \(request.query)",
              subtitle: "Try a name such as heart, kitty, smile, or flag",
              symbolName: "face.smiling"
            )
          ] : emojiRows,
        selectFirst: !emojiRows.isEmpty
      )
      return
    }

    if let word = definitionWord(in: text) {
      let definition = DictionaryLookup.definition(of: word) ?? "No definition found"
      setRows([
        Row(
          title: definition,
          subtitle: "Dictionary · \(word)",
          symbolName: "character.book.closed",
          action: "Open"
        )
      ])
      return
    }

    if let request = ChatGPTRequest(input: text) {
      let title = request.surface == .chat ? "Ask ChatGPT" : "Work in ChatGPT"
      let mode = request.surface == .chat ? "Chat" : "Work"
      setRows([
        Row(
          title: title,
          subtitle: "GPT-5.6 Sol · \(mode)",
          symbolName: "sparkles",
          action: "Open"
        )
      ])
      return
    }

    if let request = StockRequest(input: text) {
      setRows([
        Row(
          title: "Loading \(request.symbol)…",
          subtitle: "Live market quote",
          symbolName: "chart.line.uptrend.xyaxis"
        )
      ])
      stocks.fetch(request) { [weak self] quote in
        guard let self else { return }
        if let quote {
          self.setRows(
            [
              Row(
                title: quote.title,
                subtitle: quote.subtitle,
                symbolName: "chart.line.uptrend.xyaxis",
                action: "Open",
                target: .stock(quote)
              )
            ], selectFirst: true)
        } else {
          self.setRows([
            Row(
              title: "Quote unavailable",
              subtitle: "Check the ticker \(request.symbol) and try again",
              symbolName: "exclamationmark.triangle"
            )
          ])
        }
      }
      return
    }

    if let request = QuicklinkRequest(input: text, quicklinks: configStore.value.quicklinks) {
      if let destination = request.resolvedDestination {
        setRows(
          [
            Row(
              title: request.quicklink.name,
              subtitle: displayQuicklinkDestination(destination),
              symbolName: "arrow.up.right.square",
              action: "Open",
              target: .quicklink(request)
            )
          ], selectFirst: true)
      } else {
        setRows([
          Row(
            title: request.quicklink.name,
            subtitle: request.quicklink.requiresQuery
              ? "Type a query · \(request.quicklink.destination)"
              : "Invalid Quicklink destination",
            symbolName: "link"
          )
        ])
      }
      return
    }

    let exactApplication = applicationCatalog.exactMatch(named: text)
    if exactApplication == nil, let calculation = Calculator.calculate(text)
    {
      setRows(
        [
          Row(
            title: calculation.display,
            subtitle: text,
            symbolName: "equal.circle",
            action: "Copy",
            target: .calculation(calculation)
          )
        ], selectFirst: true)
      return
    }

    if let url = URLBuilder.webURL(for: text) {
      setRows([
        Row(
          title: url.host ?? text,
          subtitle: url.absoluteString,
          symbolName: "globe",
          action: "Open"
        )
      ])
      return
    }

    let preferredIdentifiers = knowledge.rankedItemIdentifiers(for: text)
    let applications = applicationCatalog.matches(
      text,
      limit: configStore.value.maxFileResults,
      preferredIdentifiers: preferredIdentifiers
    )
    let appRows = applications.map {
      Row(title: $0.name, subtitle: $0.subtitle, action: "Open", target: .application($0))
    }
    let firstIsLearned = applications.first.map {
      preferredIdentifiers.contains($0.knowledgeIdentifier)
    } ?? false
    setRows(
      appRows,
      selectFirst: exactApplication != nil || firstIsLearned
    )
  }

  private func refreshCommandCenter(_ text: String) {
    let query = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    let items = CommandCenterCatalog.items(
      query: query,
      quicklinks: configStore.value.quicklinks,
      pluginNames: availablePluginNames()
    )
    let commandRows = items.map { item in
      Row(
        title: item.title,
        subtitle: item.subtitle,
        symbolName: item.symbolName,
        action: item.action,
        target: .commandCenter(item)
      )
    }
    setRows(
      commandRows.isEmpty
        ? [
          Row(
            title: "No commands matching \(query)",
            subtitle: "Try a River action, input mode, Quicklink, or plugin",
            symbolName: "command"
          )
        ] : commandRows,
      selectFirst: !commandRows.isEmpty
    )
  }

  private func refreshPluginCommand(_ text: String) {
    let names = availablePluginNames()
    let body = String(text.dropFirst())
    let commandName =
      body.split(
        maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }
      ).first.map(String.init) ?? ""

    if let name = names.first(where: {
      $0.caseInsensitiveCompare(commandName) == .orderedSame
    }), let request = PluginRequest(input: text) {
      setRows([Row(title: "Running /\(name)…", symbolName: "terminal")])
      let normalizedRequest = PluginRequest(name: name, arguments: request.arguments)
      plugins.run(normalizedRequest, config: configStore.value) { [weak self] output in
        self?.setRows([Row(title: output, symbolName: "terminal")])
      }
      return
    }

    guard !body.contains(where: { $0.isWhitespace }) else {
      setRows([Row(title: "Unknown command /\(commandName)", symbolName: "questionmark.circle")])
      return
    }

    let normalizedPrefix = commandName.lowercased()
    let matches = names.filter {
      normalizedPrefix.isEmpty || $0.lowercased().hasPrefix(normalizedPrefix)
    }
    let suggestions = matches.map {
      Row(
        title: "/\($0)",
        subtitle: "Plugin command",
        symbolName: "terminal",
        action: "Complete",
        target: .pluginSuggestion($0)
      )
    }
    setRows(
      suggestions.isEmpty
        ? [Row(title: "No plugins matching /\(commandName)", symbolName: "terminal")]
        : suggestions,
      selectFirst: !suggestions.isEmpty
    )
  }

  private func availablePluginNames() -> [String] {
    let directory = configStore.value.pluginDirectory
    if cachedPluginDirectory == directory, let cachedPluginNames {
      return cachedPluginNames
    }

    let names = plugins.availablePlugins(in: directory)
    cachedPluginDirectory = directory
    cachedPluginNames = names
    return names
  }

  private func setRows(_ newRows: [Row], selectFirst: Bool = false) {
    rows = newRows
    setResultsVisible(false)
    selectedIndex = 0
    selectionWasExplicit = false
    updatingSelection = true
    table.reloadData()
    if selectFirst, rows.first?.target != nil {
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    updatingSelection = false
    resize(for: rows.count, display: false)
    setResultsVisible(!rows.isEmpty)
    panel.contentView?.layoutSubtreeIfNeeded()
    panel.displayIfNeeded()
  }

  private func setResultsVisible(_ visible: Bool) {
    if visible {
      NSLayoutConstraint.activate(resultsVerticalConstraints)
    } else {
      NSLayoutConstraint.deactivate(resultsVerticalConstraints)
    }
    scrollView.isHidden = !visible
    divider.isHidden = !visible
  }

  private func setStatusPlugins(_ snapshots: [StatusPluginSnapshot]) {
    guard snapshots != statusSnapshots else { return }
    let wasVisible = !statusSnapshots.isEmpty
    statusSnapshots = snapshots

    for view in statusStack.arrangedSubviews {
      statusStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for snapshot in snapshots {
      let label = NSTextField(labelWithString: snapshot.displayText)
      label.font = .systemFont(ofSize: 14.5, weight: .semibold)
      label.textColor = NSColor.white.withAlphaComponent(snapshot.output == nil ? 0.42 : 0.78)
      label.alignment = .center
      label.lineBreakMode = .byTruncatingTail
      label.maximumNumberOfLines = 1
      label.toolTip = snapshot.output
      statusStack.addArrangedSubview(label)
    }

    let isVisible = !snapshots.isEmpty
    if isVisible != wasVisible {
      if isVisible {
        mainSurfaceBottomConstraint.isActive = false
        NSLayoutConstraint.activate(statusVerticalConstraints)
      } else {
        NSLayoutConstraint.deactivate(statusVerticalConstraints)
        mainSurfaceBottomConstraint.isActive = true
      }
      statusSurface.isHidden = !isVisible
      resize(for: rows.count)
    } else if isVisible {
      panel.contentView?.layoutSubtreeIfNeeded()
      if panel.isVisible { panel.displayIfNeeded() }
    }
  }

  private func resize(for rowCount: Int, display: Bool = true) {
    let oldTop = panel.frame.maxY
    let surfaceHeight = RiverLayout.surfaceHeight(for: rowCount)
    let statusHeight = statusSnapshots.isEmpty
      ? 0 : RiverLayout.statusGap + RiverLayout.statusSurfaceHeight
    let height = surfaceHeight + statusHeight + RiverLayout.glowInset * 2
    var frame = panel.frame
    frame.size.height = height
    frame.origin.y = oldTop - height
    panel.setFrame(frame, display: false, animate: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    if display { panel.displayIfNeeded() }
  }

  private func positionOnActiveScreen() {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    var frame = panel.frame
    frame.size.width = min(RiverLayout.windowWidth, visible.width - 32)
    frame.origin.x = visible.midX - frame.width / 2
    let targetCenterY = visible.minY + visible.height * 0.62
    frame.origin.y = targetCenterY - frame.height / 2
    panel.setFrame(frame, display: false)
  }

  private func moveSelection(by offset: Int) {
    let actionableRows = rows.indices.filter { rows[$0].target != nil }
    guard !actionableRows.isEmpty else { return }
    let nextPosition: Int
    if let currentPosition = actionableRows.firstIndex(of: table.selectedRow) {
      nextPosition = max(0, min(actionableRows.count - 1, currentPosition + offset))
    } else {
      nextPosition = offset < 0 ? actionableRows.count - 1 : 0
    }
    selectedIndex = actionableRows[nextPosition]
    selectionWasExplicit = true
    updatingSelection = true
    table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
    updatingSelection = false
    table.scrollRowToVisible(selectedIndex)
  }

  private func submit() {
    let rawInput = input.stringValue
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    if text.hasPrefix(">") {
      guard rows.indices.contains(selectedIndex),
        case .commandCenter(let item)? = rows[selectedIndex].target
      else { return }
      activateCommandCenterItem(item)
      return
    }

    if incompleteInputPrompt(for: rawInput) != nil { return }

    if let command = RiverCommand(input: text) {
      perform(command)
      return
    }

    if EmojiRequest(input: text) != nil {
      if rows.indices.contains(selectedIndex),
        case .emoji(let result)? = rows[selectedIndex].target
      {
        copyToPasteboard(result.copyText)
        dismiss()
      }
      return
    }

    if let request = ChatGPTRequest(input: text),
      let url = URLBuilder.chatGPTURL(for: request)
    {
      Browser.openChatGPT(url, application: configStore.value.browser)
      dismiss()
      return
    }

    if let request = StockRequest(input: text) {
      guard let url = StockLookup.quotePageURL(for: request.symbol) else { return }
      Browser.open(url, application: configStore.value.browser)
      dismiss()
      return
    }

    if let request = QuicklinkRequest(input: text, quicklinks: configStore.value.quicklinks) {
      guard let destination = request.resolvedDestination else { return }
      open(destination)
      return
    }

    if text.hasPrefix("'"), rows.indices.contains(selectedIndex) {
      if case .file(let file)? = rows[selectedIndex].target {
        knowledge.record(
          query: String(text.dropFirst()), itemIdentifier: file.knowledgeIdentifier)
        NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        dismiss()
        return
      }
    }

    if let exactApplication = applicationCatalog.exactMatch(named: text) {
      knowledge.record(query: text, itemIdentifier: exactApplication.knowledgeIdentifier)
      open(exactApplication)
      return
    }

    if let calculation = Calculator.calculate(text) {
      copyToPasteboard(calculation.copyText)
      dismiss()
      return
    }

    if rows.indices.contains(selectedIndex),
      case .pluginSuggestion(let name)? = rows[selectedIndex].target
    {
      completePluginCommand(name)
      return
    }

    if rows.indices.contains(selectedIndex),
      case .application(let application)? = rows[selectedIndex].target
    {
      let isLearnedSelection = knowledge.hasPreference(
        for: text, itemIdentifier: application.knowledgeIdentifier)
      if selectionWasExplicit || isLearnedSelection {
        knowledge.record(query: text, itemIdentifier: application.knowledgeIdentifier)
        open(application)
        return
      }
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
      startLuckyPresentation()
      lucky.resolve(luckyURL, fallbackURL: fallbackURL) { [weak self] resolvedURL in
        guard let self else { return }
        self.stopLuckyPresentation()
        Browser.open(resolvedURL, application: self.configStore.value.browser)
        self.dismiss()
      }
      return
    }

    if let url = URLBuilder.webURL(for: text) {
      Browser.open(url, application: configStore.value.browser)
      dismiss()
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
    selectionWasExplicit = true
    submit()
  }

  private func open(_ application: ApplicationResult) {
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(
      at: application.url,
      configuration: configuration,
      completionHandler: nil
    )
    dismiss()
  }

  private func open(_ destination: QuicklinkDestination) {
    switch destination {
    case .url(let url):
      if url.scheme == "http" || url.scheme == "https" {
        Browser.open(url, application: configStore.value.browser)
      } else {
        NSWorkspace.shared.open(url)
      }
    case .file(let url):
      NSWorkspace.shared.open(url)
    }
    dismiss()
  }

  private func completePluginCommand(_ name: String) {
    replaceInput(with: "/\(name)")
  }

  private func activateCommandCenterItem(_ item: CommandCenterItem) {
    replaceInput(with: item.replacement)
    if item.submitsImmediately { submit() }
  }

  private func replaceInput(with value: String) {
    input.stringValue = value
    if let editor = panel.fieldEditor(true, for: input) as? NSTextView {
      editor.string = input.stringValue
      editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    }
    refresh(for: input.stringValue)
  }

  private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  private func startLuckyPresentation() {
    stopLuckyPresentation()
    setRows([])
    surface.startThinking()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.setRows([
        Row(
          title: "Still finding the best match…",
          subtitle: "The Lucky redirect is slow to respond. River will fall back to search if needed.",
          symbolName: "wand.and.stars"
        )
      ])
    }
    luckyStatusWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
  }

  private func stopLuckyPresentation() {
    luckyStatusWorkItem?.cancel()
    luckyStatusWorkItem = nil
    surface.stopThinking()
  }

  private func perform(_ command: RiverCommand) {
    switch command {
    case .restart:
      dismiss()
      exit(EXIT_SUCCESS)
    case .settings:
      do {
        try TerminalEditor.openInNvim(path: configStore.path)
        dismiss()
      } catch {
        setRows([
          Row(
            title: "Could not open River settings",
            subtitle: error.localizedDescription,
            symbolName: "exclamationmark.triangle"
          )
        ])
      }
    }
  }

  private func displayPath(_ path: String) -> String {
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }

  private func displayQuicklinkDestination(_ destination: QuicklinkDestination) -> String {
    switch destination {
    case .url(let url): return url.absoluteString
    case .file(let url): return displayPath(url.path)
    }
  }

  private func definitionWord(in text: String) -> String? {
    let prefix = "define "
    guard text.lowercased().hasPrefix(prefix) else { return nil }
    let word = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return word.isEmpty ? nil : word
  }

  private func incompleteInputPrompt(for rawInput: String) -> Row? {
    let normalized = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasTrailingWhitespace = rawInput.last?.isWhitespace == true
    guard hasTrailingWhitespace else { return nil }

    switch normalized {
    case "ai":
      return Row(
        title: "Type a question",
        subtitle: "ChatGPT Chat · GPT-5.6 Sol",
        symbolName: "sparkles"
      )
    case "work":
      return Row(
        title: "Describe the work",
        subtitle: "ChatGPT Work · GPT-5.6 Sol",
        symbolName: "briefcase"
      )
    case "define":
      return Row(
        title: "Type a word",
        subtitle: "Look up a Dictionary definition",
        symbolName: "character.book.closed"
      )
    case "emoji":
      return Row(
        title: "Type an emoji name",
        subtitle: "Fuzzy matching works too · try heart, hrt, cat, or kitty",
        symbolName: "face.smiling"
      )
    case "lk":
      return Row(
        title: "Type a search",
        subtitle: "Open Google's first result",
        symbolName: "wand.and.stars"
      )
    case "stock":
      return Row(
        title: "Type a ticker",
        subtitle: "Look up a live market quote",
        symbolName: "chart.line.uptrend.xyaxis"
      )
    default:
      return nil
    }
  }
}
