import XCTest

@testable import River

final class RiverTests: XCTestCase {
  func testConfigParsingAndUnknownKeys() {
    let config = AppConfig.parse(
      """
      # hello
      hotkey = cmd+space
      browser = Safari
      max_file_results = 7
      plugin_timeout_ms = 1200
      ignored = yep
      """)

    XCTAssertEqual(config.hotkey, "cmd+space")
    XCTAssertEqual(config.browser, "Safari")
    XCTAssertEqual(config.maxFileResults, 7)
    XCTAssertEqual(config.pluginTimeoutMilliseconds, 1_200)
    XCTAssertEqual(config.searchURL, AppConfig().searchURL)
  }

  func testConfigRejectsOutOfRangeNumbers() {
    let config = AppConfig.parse(
      """
      max_file_results = 999
      plugin_timeout_ms = 10
      """)
    XCTAssertEqual(config.maxFileResults, AppConfig().maxFileResults)
    XCTAssertEqual(config.pluginTimeoutMilliseconds, AppConfig().pluginTimeoutMilliseconds)
  }

  func testHotKeyParsing() {
    XCTAssertEqual(HotKeySpec("ctrl+f"), HotKeySpec("control+f"))
    XCTAssertNotNil(HotKeySpec("cmd+shift+space"))
    XCTAssertNil(HotKeySpec("f"))
    XCTAssertNil(HotKeySpec("hyper+f"))
  }

  func testPluginRequestOnlyAcceptsSafeNames() {
    XCTAssertEqual(PluginRequest(input: "/weather")?.name, "weather")
    XCTAssertEqual(PluginRequest(input: "/hello one two")?.arguments, ["one", "two"])
    XCTAssertNil(PluginRequest(input: "/../thing"))
    XCTAssertNil(PluginRequest(input: "/thing.rb"))
  }

  func testSearchURLBuilder() {
    let url = URLBuilder.searchURL(
      template: "https://www.google.com/search?q={query}",
      query: "swift & appkit"
    )
    XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=swift%20%26%20appkit")
  }

  func testSpotlightQueryTargetsFilenamesAndEscapesInput() {
    XCTAssertEqual(
      SpotlightSearch.filenamePredicate(for: "my \"file\""),
      "kMDItemFSName == \"*my \\\"file\\\"*\"cd"
    )
  }

  func testPathExpansionLeavesAbsolutePathsAlone() {
    XCTAssertEqual(Paths.expand("/tmp/plugins"), "/tmp/plugins")
    XCTAssertTrue(Paths.expand("~/plugins").hasSuffix("/plugins"))
  }

  func testConfigStoreReloadsWithoutRestart() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-config-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config")
    try "browser = Safari\n".write(to: configURL, atomically: true, encoding: .utf8)
    let store = ConfigStore(path: configURL.path)
    XCTAssertEqual(store.value.browser, "Safari")

    let reloaded = expectation(description: "config reloaded")
    store.onChange = { config in
      if config.browser == "Google Chrome" { reloaded.fulfill() }
    }
    store.startWatching()
    try "browser = Google Chrome\n".write(to: configURL, atomically: true, encoding: .utf8)

    wait(for: [reloaded], timeout: 2)
    store.stopWatching()
  }

  func testExecutableFileBecomesPlugin() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-plugin-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pluginURL = directory.appendingPathComponent("hello")
    try "#!/bin/sh\nprintf 'hello %s' \"$1\"\n".write(
      to: pluginURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pluginURL.path)

    var config = AppConfig()
    config.pluginDirectory = directory.path
    let runner = PluginRunner()
    XCTAssertEqual(runner.availablePlugins(in: directory.path), ["hello"])

    let finished = expectation(description: "plugin finished")
    runner.run(PluginRequest(input: "/hello friend")!, config: config) { output in
      XCTAssertEqual(output, "hello friend")
      finished.fulfill()
    }
    wait(for: [finished], timeout: 2)
  }

  func testGoogleLuckyRedirectIsUnwrapped() {
    let wrapper = URL(string: "https://www.google.com/url?q=https://www.apple.com/si/")!
    XCTAssertEqual(
      URLBuilder.googleRedirectTarget(from: wrapper)?.absoluteString,
      "https://www.apple.com/si/"
    )
    XCTAssertNil(URLBuilder.googleRedirectTarget(from: URL(string: "https://example.com/url?q=x")!))
  }

  func testLuckyRedirectHeaderParsing() {
    let headers = "HTTP/2 302\r\nlocation: https://www.google.com/url?q=https://apple.com/\r\n"
    XCTAssertEqual(
      LuckyResolver.redirectLocation(in: headers),
      "https://www.google.com/url?q=https://apple.com/"
    )
  }
}
