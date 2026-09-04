import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let configStore = ConfigStore()
  private let hotKey = GlobalHotKey()
  private let statusPlugins = StatusPluginManager()
  private let locationProvider = RiverLocationProvider()
  private var launcher: LauncherController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    locationProvider.onChange = { [weak self] location in
      self?.statusPlugins.update(location: location)
    }
    statusPlugins.start(config: configStore.value, location: locationProvider.currentLocation)
    let launcher = LauncherController(
      configStore: configStore,
      statusPlugins: statusPlugins,
      locationProvider: locationProvider
    )
    self.launcher = launcher

    registerHotKey(configStore.value.hotkey)
    configStore.onChange = { [weak self] config in
      self?.registerHotKey(config.hotkey)
      self?.statusPlugins.update(config: config)
      self?.launcher?.apply(config: config)
    }
    configStore.startWatching()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    locationProvider.refresh()
  }

  private func registerHotKey(_ text: String) {
    let registered = hotKey.register(text) { [weak self] in
      self?.launcher?.toggle()
    }
    if !registered {
      fputs("river: could not register hotkey '\(text)'\n", stderr)
    }
  }
}

func printUsage() {
  print(
    """
    usage: river [run|install|restart|uninstall|config|search-diagnose]

      run        run the launcher (default)
      install    install the binary, plugins, and login LaunchAgent
      restart    restart the installed launcher
      uninstall  remove the binary and LaunchAgent; keep config/plugins
      config     print the live-reloaded config path
      search-diagnose QUERY
                 print local fuzzy-search results and elapsed time
    """)
}

let command = CommandLine.arguments.dropFirst().first ?? "run"

switch command {
case "install":
  do { try Installer.install() } catch {
    fputs("river: install failed: \(error)\n", stderr)
    exit(1)
  }
case "restart":
  do { try Installer.restart() } catch {
    fputs("river: restart failed: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
case "uninstall":
  do { try Installer.uninstall() } catch {
    fputs("river: uninstall failed: \(error)\n", stderr)
    exit(1)
  }
case "config":
  print(Paths.configFile)
case "search-diagnose":
  let query = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard !query.isEmpty else {
    fputs("river: search-diagnose requires a query\n", stderr)
    exit(2)
  }

  let search = LocalFileSearch()
  let startedAt = Date()
  let deadline = startedAt.addingTimeInterval(5)
  var results: [FileResult]?
  search.search(query, limit: 10) { results = $0 }
  while results == nil, Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
  }
  search.cancel()
  guard let results else {
    fputs("river: local file search timed out\n", stderr)
    exit(1)
  }
  let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
  print("local search: \(results.count) results in \(elapsedMilliseconds) ms")
  for (index, result) in results.enumerated() {
    print("\(index + 1)\t\(result.isDirectory ? "folder" : "file")\t\(result.subtitle)")
  }
case "help", "--help", "-h":
  printUsage()
case "run":
  let application = NSApplication.shared
  application.appearance = NSAppearance(named: .darkAqua)
  let delegate = AppDelegate()
  application.delegate = delegate
  application.setActivationPolicy(.accessory)
  application.run()
default:
  printUsage()
  exit(2)
}
