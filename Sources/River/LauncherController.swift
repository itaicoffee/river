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
  var surfaceCornerRadius = RiverLayout.cornerRadius {
    didSet {
      layer?.cornerRadius = surfaceCornerRadius
      needsLayout = true
    }
  }

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
      NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.125, alpha: 1).cgColor,
      NSColor(calibratedRed: 0.025, green: 0.032, blue: 0.050, alpha: 1).cgColor,
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
    gradient.cornerRadius = surfaceCornerRadius
    layer?.shadowPath = CGPath(
      roundedRect: bounds,
      cornerWidth: surfaceCornerRadius,
      cornerHeight: surfaceCornerRadius,
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
  static let statusCornerRadius: CGFloat = 14
  static let statusGlowInset: CGFloat = 32
  static let statusSurfaceWidth: CGFloat = 296
  static let statusRowHeight: CGFloat = 40
  static let statusVerticalPadding: CGFloat = 9
  static let statusHorizontalPadding: CGFloat = 14
  static let statusScreenMargin: CGFloat = 16
  static let maximumVisibleRows = 5

  static var windowWidth: CGFloat { surfaceWidth + glowInset * 2 }
  static var restingWindowHeight: CGFloat { inputAreaHeight + glowInset * 2 }

  static func statusSurfaceHeight(for rowCount: Int) -> CGFloat {
    statusVerticalPadding * 2 + CGFloat(rowCount) * statusRowHeight
  }

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

enum StatusPluginPresentation {
  static func readableName(for displayName: String) -> String {
    displayName
      .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
      .lowercased()
  }

  static func displayValue(for snapshot: StatusPluginSnapshot) -> String {
    guard let output = snapshot.output else { return "Updating…" }
    let candidates = [
      snapshot.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      readableName(for: snapshot.displayName),
    ]

    for name in candidates.sorted(by: { $0.count > $1.count }) {
      guard output.count > name.count,
        output.prefix(name.count).caseInsensitiveCompare(name) == .orderedSame
      else { continue }

      let remainder = output.dropFirst(name.count)
        .trimmingCharacters(in: CharacterSet(charactersIn: " :-·"))
      if !remainder.isEmpty { return remainder }
    }
    return output
  }

  static func symbolName(for snapshot: StatusPluginSnapshot) -> String {
    let name = snapshot.displayName.lowercased()
    let output = snapshot.output?.lowercased() ?? ""

    if name.contains("date") || name.contains("calendar") { return "calendar" }
    if name.contains("weather") { return "sun.max.fill" }
    if name == "uv" || name.contains("ultraviolet") {
      return "sun.max.trianglebadge.exclamationmark.fill"
    }
    if name.contains("watt") || name.contains("power") { return "bolt.fill" }
    if name.contains("wifi") || name.contains("network") { return "wifi" }
    if name.contains("speed") { return "gauge.with.dots.needle.67percent" }
    if name.contains("location") { return "location.fill" }
    if name.contains("battery") { return "battery.75percent" }
    if name.contains("gmail") || name.contains("mail") { return "envelope.fill" }
    if name.contains("codex") && name.contains("context") { return "brain.head.profile" }
    if name.contains("codex") && name.contains("session") { return "clock.fill" }
    if name.contains("codex") && name.contains("week") { return "calendar.badge.clock" }
    if name.contains("stock") || name.contains("market") || output.contains("$") {
      return "chart.line.uptrend.xyaxis"
    }
    return "circle.fill"
  }
}

enum LauncherKeyAction {
  static func shouldRevealFile(modifierFlags: NSEvent.ModifierFlags) -> Bool {
    modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)
      .contains(.shift)
  }
}

private struct SpeedtestMetrics {
  let download: Double
  let upload: Double
  let isStale: Bool
  let isMeasuring: Bool
}

private final class SpeedtestMetricsView: NSView {
  private let downloadLabel = NSTextField(labelWithString: "")
  private let uploadLabel = NSTextField(labelWithString: "")
  private let downloadBar = NSView()
  private let uploadBar = NSView()
  private let downloadBarFill = NSView()
  private let uploadBarFill = NSView()

  init(metrics: SpeedtestMetrics) {
    super.init(frame: .zero)

    let textColor = NSColor.white.withAlphaComponent(metrics.isStale ? 0.56 : 0.94)
    let barColor = NSColor.white.withAlphaComponent(metrics.isStale ? 0.14 : 0.20)
    let fillColor = NSColor(calibratedRed: 0.38, green: 0.72, blue: 1.00, alpha: metrics.isStale ? 0.48 : 0.82)

    downloadLabel.stringValue = String(format: "↓%.0f", metrics.download)
    downloadLabel.font = .monospacedDigitSystemFont(ofSize: 13.5, weight: .semibold)
    downloadLabel.textColor = textColor
    downloadLabel.alignment = .right
    downloadLabel.translatesAutoresizingMaskIntoConstraints = false

    uploadLabel.stringValue = String(format: "↑%.0f", metrics.upload)
    uploadLabel.font = .monospacedDigitSystemFont(ofSize: 13.5, weight: .semibold)
    uploadLabel.textColor = textColor
    uploadLabel.alignment = .right
    uploadLabel.translatesAutoresizingMaskIntoConstraints = false

    downloadBar.wantsLayer = true
    downloadBar.layer?.backgroundColor = barColor.cgColor
    downloadBar.layer?.cornerRadius = 2
    downloadBar.translatesAutoresizingMaskIntoConstraints = false

    uploadBar.wantsLayer = true
    uploadBar.layer?.backgroundColor = barColor.cgColor
    uploadBar.layer?.cornerRadius = 2
    uploadBar.translatesAutoresizingMaskIntoConstraints = false

    downloadBarFill.wantsLayer = true
    downloadBarFill.layer?.backgroundColor = fillColor.cgColor
    downloadBarFill.layer?.cornerRadius = 2
    downloadBarFill.translatesAutoresizingMaskIntoConstraints = false

    uploadBarFill.wantsLayer = true
    uploadBarFill.layer?.backgroundColor = fillColor.cgColor
    uploadBarFill.layer?.cornerRadius = 2
    uploadBarFill.translatesAutoresizingMaskIntoConstraints = false

    let downloadStack = NSStackView(views: [downloadBar, downloadLabel])
    downloadStack.orientation = .horizontal
    downloadStack.alignment = .centerY
    downloadStack.spacing = 6
    downloadStack.translatesAutoresizingMaskIntoConstraints = false

    let uploadStack = NSStackView(views: [uploadBar, uploadLabel])
    uploadStack.orientation = .horizontal
    uploadStack.alignment = .centerY
    uploadStack.spacing = 6
    uploadStack.translatesAutoresizingMaskIntoConstraints = false

    let mainStack = NSStackView(views: [downloadStack, uploadStack])
    mainStack.orientation = .horizontal
    mainStack.alignment = .centerY
    mainStack.spacing = 8
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(mainStack)
    downloadBar.addSubview(downloadBarFill)
    uploadBar.addSubview(uploadBarFill)

    let maxSpeed = 1000.0
    let downloadFraction = min(metrics.download / maxSpeed, 1.0)
    let uploadFraction = min(metrics.upload / maxSpeed, 1.0)

    NSLayoutConstraint.activate([
      mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
      mainStack.topAnchor.constraint(equalTo: topAnchor),
      mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
      downloadBar.widthAnchor.constraint(equalToConstant: 32),
      downloadBar.heightAnchor.constraint(equalToConstant: 4),
      uploadBar.widthAnchor.constraint(equalToConstant: 32),
      uploadBar.heightAnchor.constraint(equalToConstant: 4),
      downloadLabel.widthAnchor.constraint(equalToConstant: 42),
      uploadLabel.widthAnchor.constraint(equalToConstant: 42),
      downloadBarFill.leadingAnchor.constraint(equalTo: downloadBar.leadingAnchor),
      downloadBarFill.topAnchor.constraint(equalTo: downloadBar.topAnchor),
      downloadBarFill.bottomAnchor.constraint(equalTo: downloadBar.bottomAnchor),
      downloadBarFill.widthAnchor.constraint(equalTo: downloadBar.widthAnchor, multiplier: downloadFraction),
      uploadBarFill.leadingAnchor.constraint(equalTo: uploadBar.leadingAnchor),
      uploadBarFill.topAnchor.constraint(equalTo: uploadBar.topAnchor),
      uploadBarFill.bottomAnchor.constraint(equalTo: uploadBar.bottomAnchor),
      uploadBarFill.widthAnchor.constraint(equalTo: uploadBar.widthAnchor, multiplier: uploadFraction),
    ])
  }

  required init?(coder: NSCoder) { nil }
}

private final class StatusPluginRowView: NSView {
  private let iconPlate = NSView()
  private let iconView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let valueLabel = NSTextField(labelWithString: "")
  private let divider = NSView()
  private var speedtestMetricsView: SpeedtestMetricsView?

  init(snapshot: StatusPluginSnapshot, showsDivider: Bool) {
    super.init(frame: .zero)

    let tint = Self.tint(for: snapshot)
    iconPlate.wantsLayer = true
    iconPlate.layer?.cornerRadius = 8
    if #available(macOS 10.15, *) { iconPlate.layer?.cornerCurve = .continuous }
    iconPlate.layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
    iconPlate.layer?.borderWidth = 0.5
    iconPlate.layer?.borderColor = tint.withAlphaComponent(0.22).cgColor
    iconPlate.translatesAutoresizingMaskIntoConstraints = false

    iconView.image = NSImage(
      systemSymbolName: StatusPluginPresentation.symbolName(for: snapshot),
      accessibilityDescription: nil
    ) ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
    iconView.contentTintColor = tint.withAlphaComponent(0.92)
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    let readableName = StatusPluginPresentation.readableName(for: snapshot.displayName)
    nameLabel.stringValue = readableName
    nameLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
    nameLabel.textColor = NSColor.white.withAlphaComponent(0.62)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    nameLabel.translatesAutoresizingMaskIntoConstraints = false

    valueLabel.stringValue = StatusPluginPresentation.displayValue(for: snapshot)
    valueLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
    valueLabel.textColor = NSColor.white.withAlphaComponent(snapshot.output == nil ? 0.42 : 0.94)
    valueLabel.alignment = .right
    valueLabel.lineBreakMode = .byTruncatingTail
    valueLabel.setContentHuggingPriority(.required, for: .horizontal)
    valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    valueLabel.translatesAutoresizingMaskIntoConstraints = false

    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
    divider.isHidden = !showsDivider
    divider.translatesAutoresizingMaskIntoConstraints = false

    addSubview(iconPlate)
    iconPlate.addSubview(iconView)
    addSubview(nameLabel)
    addSubview(divider)

    if let metrics = Self.parseSpeedtest(snapshot: snapshot) {
      let metricsView = SpeedtestMetricsView(metrics: metrics)
      metricsView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(metricsView)
      speedtestMetricsView = metricsView
      valueLabel.isHidden = true

      NSLayoutConstraint.activate([
        metricsView.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 10),
        metricsView.trailingAnchor.constraint(equalTo: trailingAnchor),
        metricsView.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
    } else {
      addSubview(valueLabel)
      NSLayoutConstraint.activate([
        valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 10),
        valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
    }

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: RiverLayout.statusRowHeight),
      iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor),
      iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconPlate.widthAnchor.constraint(equalToConstant: 26),
      iconPlate.heightAnchor.constraint(equalToConstant: 26),
      iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 14),
      iconView.heightAnchor.constraint(equalToConstant: 14),
      nameLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
      nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      divider.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: trailingAnchor),
      divider.bottomAnchor.constraint(equalTo: bottomAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
    ])

    setAccessibilityElement(true)
    setAccessibilityLabel("\(readableName), \(snapshot.displayText)")
  }

  required init?(coder: NSCoder) { nil }

  private static func parseSpeedtest(snapshot: StatusPluginSnapshot) -> SpeedtestMetrics? {
    guard snapshot.displayName.lowercased().contains("speed"),
          let output = snapshot.output else { return nil }
    
    let pattern = "↓([0-9.]+)\\s*↑([0-9.]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
          match.numberOfRanges == 3,
          let downloadRange = Range(match.range(at: 1), in: output),
          let uploadRange = Range(match.range(at: 2), in: output),
          let download = Double(output[downloadRange]),
          let upload = Double(output[uploadRange]) else { return nil }
    
    let isStale = output.contains("(…)")
    let isMeasuring = output.contains("measuring")
    
    return SpeedtestMetrics(
      download: download,
      upload: upload,
      isStale: isStale,
      isMeasuring: isMeasuring
    )
  }

  private static func tint(for snapshot: StatusPluginSnapshot) -> NSColor {
    let normalized = snapshot.displayName.lowercased()
    let output = snapshot.output?.lowercased() ?? ""
    if output.contains("authentication") || output.contains("error") {
      return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.38, alpha: 1)
    }
    if normalized.contains("weather") {
      return NSColor(calibratedRed: 1.00, green: 0.67, blue: 0.24, alpha: 1)
    }
    if normalized == "uv" || normalized.contains("ultraviolet") {
      return NSColor(calibratedRed: 0.75, green: 0.50, blue: 1.00, alpha: 1)
    }
    if normalized.contains("watt") || normalized.contains("power") {
      return NSColor(calibratedRed: 0.37, green: 0.84, blue: 0.62, alpha: 1)
    }
    if normalized.contains("stock") || normalized.contains("market") {
      return NSColor(calibratedRed: 0.32, green: 0.78, blue: 0.96, alpha: 1)
    }
    if normalized.contains("location") {
      return NSColor(calibratedRed: 0.39, green: 0.78, blue: 1.00, alpha: 1)
    }
    if normalized.contains("battery") {
      return NSColor(calibratedRed: 0.39, green: 0.86, blue: 0.57, alpha: 1)
    }
    if normalized.contains("gmail") || normalized.contains("mail") {
      return NSColor(calibratedRed: 0.96, green: 0.48, blue: 0.42, alpha: 1)
    }
    if normalized.contains("codex") {
      return NSColor(calibratedRed: 0.72, green: 0.57, blue: 1.00, alpha: 1)
    }
    return NSColor(calibratedRed: 0.38, green: 0.72, blue: 1.00, alpha: 1)
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
  private let locationProvider: RiverLocationProvider
  private let fileSearch = FileSearchEngine()
  private let plugins = PluginRunner()
  private let lucky = LuckyResolver()
  private let stocks = StockLookup()
  private let applicationCatalog = ApplicationCatalog()
  private let knowledge: ResultKnowledge
  private let panel: LauncherPanel
  private let statusPanel: NSPanel
  private let surface = GlowView()
  private let statusSurface = GlowView()
  private let statusStack = NSStackView()
  private let input = NSTextField()
  private let table = NSTableView()
  private let scrollView = NSScrollView()
  private let divider = NSView()
  private let fileIconCache = NSCache<NSString, NSImage>()
  private var resultsVerticalConstraints: [NSLayoutConstraint] = []
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
    locationProvider: RiverLocationProvider,
    knowledge: ResultKnowledge = ResultKnowledge()
  ) {
    self.configStore = configStore
    self.statusPlugins = statusPlugins
    self.locationProvider = locationProvider
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
    statusPanel = NSPanel(
      contentRect: .zero,
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
    if !statusSnapshots.isEmpty { statusPanel.orderFront(nil) }
    panel.makeFirstResponder(input)
    // Core Location only presents its authorization sheet once the application
    // is in the foreground. Activation is asynchronous for an accessory app.
    DispatchQueue.main.async { [weak locationProvider] in
      locationProvider?.refresh()
    }
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
    fileSearch.cancel()
    plugins.cancel()
    lucky.cancel()
    stocks.cancel()
    stopLuckyPresentation()
    panel.orderOut(nil)
    statusPanel.orderOut(nil)
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
      submit(
        revealFileInFinder: LauncherKeyAction.shouldRevealFile(
          modifierFlags: NSApp.currentEvent?.modifierFlags ?? []
        )
      )
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

    statusPanel.level = .floating
    statusPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    statusPanel.isOpaque = false
    statusPanel.backgroundColor = .clear
    statusPanel.hasShadow = false
    statusPanel.hidesOnDeactivate = true
    statusPanel.ignoresMouseEvents = true
    statusPanel.isReleasedWhenClosed = false
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
    statusSurface.surfaceCornerRadius = RiverLayout.statusCornerRadius
    statusSurface.layer?.cornerRadius = RiverLayout.statusCornerRadius
    if #available(macOS 10.15, *) { statusSurface.layer?.cornerCurve = .continuous }
    statusSurface.layer?.masksToBounds = false
    statusSurface.layer?.borderWidth = 1
    statusSurface.layer?.borderColor = NSColor(
      calibratedRed: 0.28,
      green: 0.55,
      blue: 0.82,
      alpha: 0.30
    ).cgColor
    statusSurface.layer?.shadowColor = NSColor(
      calibratedRed: 0.02,
      green: 0.25,
      blue: 0.55,
      alpha: 1
    ).cgColor
    statusSurface.layer?.shadowOpacity = 0.26
    statusSurface.layer?.shadowRadius = 14
    statusSurface.layer?.shadowOffset = CGSize(width: 0, height: -3)
    statusSurface.isHidden = true
    statusSurface.translatesAutoresizingMaskIntoConstraints = false

    statusStack.orientation = .vertical
    statusStack.alignment = .leading
    statusStack.distribution = .fill
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
    panel.contentView = root

    let statusRoot = NSView()
    statusRoot.wantsLayer = true
    statusRoot.layer?.backgroundColor = NSColor.clear.cgColor
    statusRoot.addSubview(statusSurface)
    statusPanel.contentView = statusRoot

    resultsVerticalConstraints = [
      scrollView.topAnchor.constraint(
        equalTo: divider.bottomAnchor, constant: RiverLayout.resultsTopInset),
      scrollView.bottomAnchor.constraint(
        equalTo: surface.bottomAnchor, constant: -RiverLayout.resultsBottomInset),
    ]
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
      statusStack.leadingAnchor.constraint(
        equalTo: statusSurface.leadingAnchor,
        constant: RiverLayout.statusHorizontalPadding
      ),
      statusStack.trailingAnchor.constraint(
        equalTo: statusSurface.trailingAnchor,
        constant: -RiverLayout.statusHorizontalPadding
      ),
      statusStack.topAnchor.constraint(
        equalTo: statusSurface.topAnchor, constant: RiverLayout.statusVerticalPadding),
      statusStack.bottomAnchor.constraint(
        equalTo: statusSurface.bottomAnchor, constant: -RiverLayout.statusVerticalPadding),
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

    NSLayoutConstraint.activate([
      statusSurface.leadingAnchor.constraint(
        equalTo: statusRoot.leadingAnchor, constant: RiverLayout.statusGlowInset),
      statusSurface.trailingAnchor.constraint(
        equalTo: statusRoot.trailingAnchor, constant: -RiverLayout.statusGlowInset),
      statusSurface.topAnchor.constraint(
        equalTo: statusRoot.topAnchor, constant: RiverLayout.statusGlowInset),
      statusSurface.bottomAnchor.constraint(
        equalTo: statusRoot.bottomAnchor, constant: -RiverLayout.statusGlowInset),
    ])
  }

  private func refresh(for rawInput: String) {
    fileSearch.cancel()
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
      case .restartComputer:
        setRows([
          Row(
            title: "Restart this Mac",
            subtitle: "System · Close apps and restart",
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
      case .shutDown:
        setRows([
          Row(
            title: "Shut down this Mac",
            subtitle: "System · Close apps and power off",
            symbolName: "power",
            action: "Shut Down"
          )
        ])
      case .lock:
        setRows([
          Row(
            title: "Lock Screen",
            subtitle: "System · Require sign-in to continue",
            symbolName: "lock",
            action: "Lock"
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
      let query = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        setRows([
          Row(
            title: "Type a filename",
            subtitle: "Fuzzy-search files and folders on this Mac",
            symbolName: "doc.text.magnifyingglass"
          )
        ])
        return
      }
      setRows([Row(title: "Searching…", symbolName: "magnifyingglass")])
      let resultLimit = configStore.value.maxFileResults
      let preferredIdentifiers = knowledge.rankedItemIdentifiers(for: query)
      fileSearch.search(
        query,
        limit: resultLimit,
        preferredIdentifiers: preferredIdentifiers
      ) { [weak self] results, isFinal in
        guard let self else { return }
        let rows = results.map {
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
            ? [
              Row(
                title: isFinal ? "No files found" : "Searching…",
                symbolName: isFinal ? "doc.text.magnifyingglass" : "magnifyingglass"
              )
            ] : rows,
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
      plugins.run(
        normalizedRequest,
        config: configStore.value,
        environment: locationProvider.currentLocation?.pluginEnvironment ?? [:]
      ) { [weak self] output in
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
    for (index, snapshot) in snapshots.enumerated() {
      let row = StatusPluginRowView(
        snapshot: snapshot,
        showsDivider: index < snapshots.count - 1
      )
      statusStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: statusStack.widthAnchor).isActive = true
    }

    let isVisible = !snapshots.isEmpty
    statusSurface.isHidden = !isVisible
    if isVisible {
      positionStatusPanel()
      statusPanel.contentView?.layoutSubtreeIfNeeded()
      if panel.isVisible {
        statusPanel.orderFront(nil)
        statusPanel.displayIfNeeded()
      }
    } else if wasVisible {
      statusPanel.orderOut(nil)
    }
  }

  private func resize(for rowCount: Int, display: Bool = true) {
    let oldTop = panel.frame.maxY
    let surfaceHeight = RiverLayout.surfaceHeight(for: rowCount)
    let height = surfaceHeight + RiverLayout.glowInset * 2
    var frame = panel.frame
    frame.size.height = height
    frame.origin.y = oldTop - height
    panel.setFrame(frame, display: false, animate: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    if display { panel.displayIfNeeded() }
  }

  private func positionOnActiveScreen() {
    let screen = activeScreen()
    guard let visible = screen?.visibleFrame else { return }
    var frame = panel.frame
    frame.size.width = min(RiverLayout.windowWidth, visible.width - 32)
    frame.origin.x = visible.midX - frame.width / 2
    let targetCenterY = visible.minY + visible.height * 0.62
    frame.origin.y = targetCenterY - frame.height / 2
    panel.setFrame(frame, display: false)
    positionStatusPanel(on: screen)
  }

  private func activeScreen() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
  }

  private func positionStatusPanel(on screen: NSScreen? = nil) {
    guard !statusSnapshots.isEmpty, let visible = (screen ?? activeScreen())?.visibleFrame else {
      return
    }
    let surfaceHeight = RiverLayout.statusSurfaceHeight(for: statusSnapshots.count)
    let width = RiverLayout.statusSurfaceWidth + RiverLayout.statusGlowInset * 2
    let height = surfaceHeight + RiverLayout.statusGlowInset * 2
    let frame = NSRect(
      x: visible.minX + RiverLayout.statusScreenMargin - RiverLayout.statusGlowInset,
      y: visible.maxY - RiverLayout.statusScreenMargin - surfaceHeight
        - RiverLayout.statusGlowInset,
      width: width,
      height: height
    )
    statusPanel.setFrame(frame, display: false)
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

  private func submit(revealFileInFinder: Bool = false) {
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
      Browser.openChatGPT(url)
      dismiss()
      return
    }

    if let request = StockRequest(input: text) {
      guard let url = StockLookup.quotePageURL(for: request.symbol) else { return }
      Browser.open(url)
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
        let url = URL(fileURLWithPath: file.path)
        if revealFileInFinder {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
          NSWorkspace.shared.open(url)
        }
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
        Browser.open(resolvedURL)
        self.dismiss()
      }
      return
    }

    if let url = URLBuilder.webURL(for: text) {
      Browser.open(url)
      dismiss()
      return
    }

    guard let url = URLBuilder.searchURL(template: configStore.value.searchURL, query: text) else {
      return
    }
    Browser.open(url)
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
        Browser.open(url)
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
    case .restartComputer:
      perform(MacSystemAction.restart)
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
    case .shutDown:
      perform(MacSystemAction.shutDown)
    case .lock:
      perform(MacSystemAction.lock)
    }
  }

  private func perform(_ action: MacSystemAction) {
    do {
      try action.perform()
      dismiss()
    } catch {
      setRows([
        Row(
          title: "Could not perform system action",
          subtitle: error.localizedDescription,
          symbolName: "exclamationmark.triangle"
        )
      ])
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
