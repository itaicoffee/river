import Foundation

struct Quicklink: Equatable {
  let name: String
  let destination: String

  var requiresQuery: Bool { destination.contains("{query}") }
}

struct AppConfig: Equatable {
  var hotkey = "ctrl+f"
  var searchURL = "https://www.google.com/search?q={query}"
  var luckyURL = "https://www.google.com/search?btnI=1&q={query}"
  var pluginDirectory = "~/.config/river/plugins"
  var pluginTimeoutMilliseconds = 5_000
  var maxFileResults = 5
  var quicklinks: [Quicklink] = []

  static let defaultText = """
    # River reloads this file automatically. No restart is needed.
    hotkey = ctrl+f
    search_url = https://www.google.com/search?q={query}
    lucky_url = https://www.google.com/search?btnI=1&q={query}
    plugin_dir = ~/.config/river/plugins
    plugin_timeout_ms = 5000
    max_file_results = 5
    # quicklink.github = https://github.com/search?q={query}
    # quicklink.project = ~/Documents/code/project
    """

  static func parse(_ text: String) -> AppConfig {
    var config = AppConfig()

    for rawLine in text.split(whereSeparator: { $0.isNewline }) {
      let line = String(rawLine).trimmingCharacters(in: CharacterSet.whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
        continue
      }

      let key = String(line[..<separator]).trimmingCharacters(in: CharacterSet.whitespaces)
      let value = String(line[line.index(after: separator)...]).trimmingCharacters(
        in: CharacterSet.whitespaces)
      guard !value.isEmpty else { continue }

      switch key {
      case "hotkey": config.hotkey = value
      case "search_url": config.searchURL = value
      case "lucky_url": config.luckyURL = value
      case "plugin_dir": config.pluginDirectory = value
      case "plugin_timeout_ms":
        if let milliseconds = Int(value), (250...30_000).contains(milliseconds) {
          config.pluginTimeoutMilliseconds = milliseconds
        }
      case "max_file_results":
        if let count = Int(value), (1...10).contains(count) {
          config.maxFileResults = count
        }
      case let key where key.hasPrefix("quicklink."):
        let name = String(key.dropFirst("quicklink.".count))
          .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
          name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else { continue }

        let quicklink = Quicklink(name: name, destination: value)
        if let index = config.quicklinks.firstIndex(where: {
          $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
          config.quicklinks[index] = quicklink
        } else {
          config.quicklinks.append(quicklink)
        }
      default: continue
      }
    }

    return config
  }
}

final class ConfigStore {
  let path: String
  private(set) var value: AppConfig
  var onChange: ((AppConfig) -> Void)?

  private var timer: Timer?
  private var lastContents: Data?

  init(path: String = Paths.configFile) {
    self.path = path
    let contents = FileManager.default.contents(atPath: path)
    self.lastContents = contents
    self.value =
      contents.flatMap { String(data: $0, encoding: .utf8) }.map(AppConfig.parse) ?? AppConfig()
  }

  func startWatching() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.reloadIfNeeded()
    }
  }

  func stopWatching() {
    timer?.invalidate()
    timer = nil
  }

  private func reloadIfNeeded() {
    let contents = FileManager.default.contents(atPath: path)
    guard contents != lastContents else { return }
    lastContents = contents

    let updated =
      contents.flatMap { String(data: $0, encoding: .utf8) }.map(AppConfig.parse) ?? AppConfig()
    guard updated != value else { return }
    value = updated
    onChange?(updated)
  }

  deinit {
    stopWatching()
  }
}

enum Paths {
  static var homeDirectory: String {
    ProcessInfo.processInfo.environment["RIVER_HOME"]
      ?? ProcessInfo.processInfo.environment["HOME"]
      ?? NSHomeDirectory()
  }

  static var configFile: String {
    ProcessInfo.processInfo.environment["RIVER_CONFIG"]
      ?? expand("~/.config/river/config")
  }

  static var knowledgeFile: String {
    ProcessInfo.processInfo.environment["RIVER_KNOWLEDGE"]
      ?? URL(fileURLWithPath: configFile).deletingLastPathComponent()
        .appendingPathComponent("knowledge.json").path
  }

  static var statusPluginCacheFile: String {
    ProcessInfo.processInfo.environment["RIVER_STATUS_PLUGIN_CACHE"]
      ?? expand("~/.cache/river/status-plugins.json")
  }

  static var locationCacheFile: String {
    ProcessInfo.processInfo.environment["RIVER_LOCATION_CACHE"]
      ?? expand("~/.cache/river/location.json")
  }

  static var installedBinary: String {
    expand("~/.local/bin/river")
  }

  static var installedApp: String {
    expand("~/Library/Application Support/River/River.app")
  }

  static var installedAppBinary: String {
    URL(fileURLWithPath: installedApp).appendingPathComponent("Contents/MacOS/river").path
  }

  static var launchAgent: String {
    expand("~/Library/LaunchAgents/dev.itai.river.plist")
  }

  static func expand(_ path: String) -> String {
    if path == "~" { return homeDirectory }
    if path.hasPrefix("~/") { return homeDirectory + path.dropFirst() }
    return path
  }

  static var legacyConfigDirectory: String { expand("~/.config/prompt") }
  static var legacyInstalledBinary: String { expand("~/.local/bin/prompt") }
  static var legacyLaunchAgent: String {
    expand("~/Library/LaunchAgents/dev.itai.prompt.plist")
  }
}
