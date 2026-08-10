import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let configStore = ConfigStore()
  private let hotKey = GlobalHotKey()
  private var launcher: LauncherController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let launcher = LauncherController(configStore: configStore)
    self.launcher = launcher

    registerHotKey(configStore.value.hotkey)
    configStore.onChange = { [weak self] config in
      self?.registerHotKey(config.hotkey)
    }
    configStore.startWatching()
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
    usage: river [run|install|restart|uninstall|config]

      run        run the launcher (default)
      install    install the binary, plugins, and login LaunchAgent
      restart    restart the installed launcher
      uninstall  remove the binary and LaunchAgent; keep config/plugins
      config     print the live-reloaded config path
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
