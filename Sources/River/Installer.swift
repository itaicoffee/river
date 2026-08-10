import Foundation

enum Installer {
  static let label = "dev.itai.river"
  private static let legacyLabel = "dev.itai.prompt"

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
      guard !FileManager.default.fileExists(atPath: url.path) else { continue }
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

  private static func runLaunchctl(_ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  private static let defaultPlugins: [String: String] = [
    "uv": """
    #!/bin/zsh
    value=$(/usr/bin/curl -fsS --max-time 5 'https://wttr.in/?format=%u' 2>/dev/null)
    value=${value//$'\\n'/}
    if [[ "$value" == <-> ]]; then
      print "UV $value"
    else
      print "UV unavailable"
    fi
    """,
    "weather": """
    #!/bin/zsh
    value=$(/usr/bin/curl -fsS --max-time 5 'https://wttr.in/?format=%t&m' 2>/dev/null)
    value=${value//$'\\n'/}
    if [[ -n "$value" ]]; then
      print -- "${value/+}"
    else
      print "Weather unavailable"
    fi
    """,
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
  ]
}
