import Foundation

enum Installer {
  static let label = "dev.itai.river"
  private static let legacyLabel = "dev.itai.prompt"

  private enum InstallerError: LocalizedError {
    case notInstalled
    case notRunning
    case restartFailed(String)

    var errorDescription: String? {
      switch self {
      case .notInstalled:
        return "River is not installed; run 'river install' first"
      case .notRunning:
        return "the River LaunchAgent is not running"
      case .restartFailed(let reason):
        return reason
      }
    }
  }

  static func install() throws {
    let fileManager = FileManager.default
    let sourceBinary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let destinationBinary = URL(fileURLWithPath: Paths.installedBinary)

    try fileManager.createDirectory(
      at: destinationBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
    if sourceBinary.path != destinationBinary.path {
      if fileManager.fileExists(atPath: destinationBinary.path) {
        try fileManager.removeItem(at: destinationBinary)
      }
      try fileManager.copyItem(at: sourceBinary, to: destinationBinary)
    }
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationBinary.path)

    try migrateLegacyConfigurationIfNeeded()
    try seedConfiguration()
    try seedPlugins()
    try writeLaunchAgent()
    unloadLegacyLaunchAgent()
    reloadLaunchAgent()
    try removeLegacyRuntime()

    print("Installed River")
    print("  binary: \(Paths.installedBinary)")
    print("  config: \(Paths.configFile)")
    print("  hotkey: Ctrl+F")
  }

  static func uninstall() throws {
    unloadLaunchAgent()
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: Paths.launchAgent) {
      try fileManager.removeItem(atPath: Paths.launchAgent)
    }
    if fileManager.fileExists(atPath: Paths.installedBinary) {
      try fileManager.removeItem(atPath: Paths.installedBinary)
    }
    print("Uninstalled River. Your config and plugins were kept at ~/.config/river.")
  }

  static func restart() throws {
    guard FileManager.default.fileExists(atPath: Paths.launchAgent) else {
      throw InstallerError.notInstalled
    }
    guard ProcessInfo.processInfo.environment["RIVER_SKIP_LAUNCHCTL"] != "1" else { return }

    guard let pid = runningLaunchAgentPID() else { throw InstallerError.notRunning }
    guard kill(pid, SIGTERM) == 0 else {
      throw InstallerError.restartFailed(String(cString: strerror(errno)))
    }
    print("Restarted River")
  }

  static func runningPID(in launchctlOutput: String) -> pid_t? {
    for line in launchctlOutput.split(whereSeparator: { $0.isNewline }) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("pid = ") else { continue }
      return pid_t(trimmed.dropFirst("pid = ".count))
    }
    return nil
  }

  private static func seedConfiguration() throws {
    let fileManager = FileManager.default
    let configURL = URL(fileURLWithPath: Paths.configFile)
    try fileManager.createDirectory(
      at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: configURL.path) {
      try AppConfig.defaultText.write(to: configURL, atomically: true, encoding: .utf8)
    }
  }

  private static func seedPlugins() throws {
    let configText =
      (try? String(contentsOfFile: Paths.configFile, encoding: .utf8)) ?? AppConfig.defaultText
    let pluginDirectory = URL(
      fileURLWithPath: Paths.expand(AppConfig.parse(configText).pluginDirectory))
    try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

    for (name, contents) in defaultPlugins {
      let url = pluginDirectory.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: url.path) {
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let shouldMigrate =
          (name == "weather"
            && (existing == legacyWeatherPlugin || existing == pinnedWeatherPlugin))
          || (name == "uv" && (existing == legacyUVPlugin || existing == pinnedUVPlugin))
        if shouldMigrate {
          try contents.write(to: url, atomically: true, encoding: .utf8)
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        continue
      }
      try contents.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
  }

  private static func writeLaunchAgent() throws {
    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": [Paths.installedBinary, "run"],
      "RunAtLoad": true,
      "KeepAlive": true,
      "ProcessType": "Interactive",
      "LimitLoadToSessionType": "Aqua",
      "StandardOutPath": "/tmp/river.log",
      "StandardErrorPath": "/tmp/river.log",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let url = URL(fileURLWithPath: Paths.launchAgent)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  private static func reloadLaunchAgent() {
    guard ProcessInfo.processInfo.environment["RIVER_SKIP_LAUNCHCTL"] != "1" else { return }
    unloadLaunchAgent()
    runLaunchctl(["bootstrap", "gui/\(getuid())", Paths.launchAgent])
  }

  private static func unloadLaunchAgent() {
    guard ProcessInfo.processInfo.environment["RIVER_SKIP_LAUNCHCTL"] != "1" else { return }
    runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
  }

  private static func unloadLegacyLaunchAgent() {
    guard ProcessInfo.processInfo.environment["RIVER_SKIP_LAUNCHCTL"] != "1" else { return }
    runLaunchctl(["bootout", "gui/\(getuid())/\(legacyLabel)"])
  }

  private static func migrateLegacyConfigurationIfNeeded() throws {
    guard ProcessInfo.processInfo.environment["RIVER_CONFIG"] == nil else { return }
    let fileManager = FileManager.default
    let legacyDirectory = URL(fileURLWithPath: Paths.legacyConfigDirectory)
    let riverDirectory = URL(fileURLWithPath: Paths.expand("~/.config/river"))
    guard fileManager.fileExists(atPath: legacyDirectory.path),
      !fileManager.fileExists(atPath: riverDirectory.path)
    else {
      return
    }

    try fileManager.createDirectory(
      at: riverDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.moveItem(at: legacyDirectory, to: riverDirectory)

    let configURL = riverDirectory.appendingPathComponent("config")
    guard var text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
    text =
      text
      .replacingOccurrences(of: "# Prompt", with: "# River")
      .replacingOccurrences(of: "~/.config/prompt/plugins", with: "~/.config/river/plugins")
    try text.write(to: configURL, atomically: true, encoding: .utf8)
  }

  private static func removeLegacyRuntime() throws {
    let fileManager = FileManager.default
    for path in [Paths.legacyInstalledBinary, Paths.legacyLaunchAgent] {
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    }
  }

  private static func runningLaunchAgentPID() -> pid_t? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", "gui/\(getuid())/\(label)"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    return runningPID(in: text)
  }

  @discardableResult
  private static func runLaunchctl(_ arguments: [String], suppressOutput: Bool = true) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    if suppressOutput {
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
    }
    do {
      try process.run()
    } catch {
      return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
  }

  static let defaultStatusPluginNames = [
    "010-weather.10m.zsh",
    "020-uv.15m.zsh",
    "030-watts.10s.zsh",
  ]

  static let legacyWeatherPlugin = """
    #!/bin/zsh
    value=$(/usr/bin/curl -fsS --max-time 5 'https://wttr.in/?format=%t&m' 2>/dev/null)
    value=${value//$'\\n'/}
    if [[ -n "$value" ]]; then
      print -- "${value/+}"
    else
      print "Weather unavailable"
    fi
    """

  static let pinnedWeatherPlugin = """
    #!/bin/zsh
    payload=$(/usr/bin/curl -fsS --max-time 5 \\
      'https://api.open-meteo.com/v1/forecast?latitude=45.82&longitude=13.84&current=temperature_2m&timezone=Europe%2FLjubljana' \\
      2>/dev/null)
    temperature=$(print -r -- "$payload" | /usr/bin/sed -nE \\
      's/.*"temperature_2m":(-?[0-9]+(\\.[0-9]+)?).*/\\1/p')
    if [[ -n "$temperature" ]]; then
      LC_NUMERIC=C /usr/bin/printf '%.0f°C\\n' "$temperature"
    else
      print "Weather unavailable"
    fi
    """

  static let weatherPlugin = """
    #!/bin/zsh
    if [[ -z "$RIVER_LATITUDE" || -z "$RIVER_LONGITUDE" ]]; then
      print "Weather unavailable"
      exit 0
    fi
    payload=$(/usr/bin/curl -fsS --max-time 5 \\
      "https://api.open-meteo.com/v1/forecast?latitude=${RIVER_LATITUDE}&longitude=${RIVER_LONGITUDE}&current=temperature_2m&timezone=auto" \\
      2>/dev/null)
    temperature=$(print -r -- "$payload" | /usr/bin/sed -nE \\
      's/.*"temperature_2m":(-?[0-9]+(\\.[0-9]+)?).*/\\1/p')
    if [[ -n "$temperature" ]]; then
      LC_NUMERIC=C /usr/bin/printf '%.0f°C\\n' "$temperature"
    else
      print "Weather unavailable"
    fi
    """

  static let legacyUVPlugin = """
    #!/bin/zsh
    value=$(/usr/bin/curl -fsS --max-time 5 'https://wttr.in/?format=%u' 2>/dev/null)
    value=${value//$'\\n'/}
    if [[ "$value" == <-> ]]; then
      print "UV $value"
    else
      print "UV unavailable"
    fi
    """

  static let pinnedUVPlugin = """
    #!/bin/zsh
    payload=$(/usr/bin/curl -fsS --max-time 5 \\
      'https://api.open-meteo.com/v1/forecast?latitude=45.82&longitude=13.84&current=uv_index&timezone=Europe%2FRome' \\
      2>/dev/null)
    uv=$(print -r -- "$payload" | /usr/bin/sed -nE \\
      's/.*"uv_index":(-?[0-9]+(\\.[0-9]+)?).*/\\1/p')
    if [[ -n "$uv" ]]; then
      LC_NUMERIC=C /usr/bin/printf 'UV %.1f\\n' "$uv"
    else
      print "UV unavailable"
    fi
    """

  static let uvPlugin = """
    #!/bin/zsh
    if [[ -z "$RIVER_LATITUDE" || -z "$RIVER_LONGITUDE" ]]; then
      print "UV unavailable"
      exit 0
    fi
    payload=$(/usr/bin/curl -fsS --max-time 5 \\
      "https://api.open-meteo.com/v1/forecast?latitude=${RIVER_LATITUDE}&longitude=${RIVER_LONGITUDE}&current=uv_index&timezone=auto" \\
      2>/dev/null)
    uv=$(print -r -- "$payload" | /usr/bin/sed -nE \\
      's/.*"uv_index":(-?[0-9]+(\\.[0-9]+)?).*/\\1/p')
    if [[ -n "$uv" ]]; then
      LC_NUMERIC=C /usr/bin/printf 'UV %.1f\\n' "$uv"
    else
      print "UV unavailable"
    fi
    """

  private static let defaultPlugins: [String: String] = [
    "uv": uvPlugin,
    "weather": weatherPlugin,
    "watts": """
    #!/bin/zsh
    power=$(/usr/sbin/system_profiler SPPowerDataType 2>/dev/null)
    connected=$(print -r -- "$power" | /usr/bin/awk -F': ' '/Connected:/{print $2; exit}')
    watts=$(print -r -- "$power" | /usr/bin/awk -F': ' '/Wattage \\(W\\):/{print $2; exit}')
    if [[ -n "$watts" ]]; then
      print "${watts}W charger"
    elif [[ "$connected" == "Yes" ]]; then
      print "Charger connected · wattage unavailable"
    else
      print "No charger"
    fi
    """,
    "010-weather.10m.zsh": """
    #!/bin/zsh
    exec "${0:A:h}/weather"
    """,
    "020-uv.15m.zsh": """
    #!/bin/zsh
    exec "${0:A:h}/uv"
    """,
    "030-watts.10s.zsh": """
    #!/bin/zsh
    exec "${0:A:h}/watts"
    """,
  ]
}
