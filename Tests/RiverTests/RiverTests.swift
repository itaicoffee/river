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
      quicklink.github = https://github.com/search?q={query}
      ignored = yep
      """)

    XCTAssertEqual(config.hotkey, "cmd+space")
    XCTAssertEqual(config.browser, "Safari")
    XCTAssertEqual(config.maxFileResults, 7)
    XCTAssertEqual(config.pluginTimeoutMilliseconds, 1_200)
    XCTAssertEqual(config.searchURL, AppConfig().searchURL)
    XCTAssertEqual(
      config.quicklinks,
      [Quicklink(name: "github", destination: "https://github.com/search?q={query}")]
    )
  }

  func testConfigQuicklinksRejectUnsafeNamesAndReplaceDuplicates() {
    let config = AppConfig.parse(
      """
      quicklink.docs = https://example.com/old
      quicklink.bad name = https://example.com/nope
      quicklink.DOCS = https://example.com/new
      """)

    XCTAssertEqual(
      config.quicklinks,
      [Quicklink(name: "DOCS", destination: "https://example.com/new")]
    )
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

  func testCalculatorEvaluatesArithmeticPercentagesAndFunctions() {
    XCTAssertEqual(Calculator.calculate("2 + 3 * 4")?.copyText, "14")
    XCTAssertEqual(Calculator.calculate("2 ^ 3 ^ 2")?.copyText, "512")
    XCTAssertEqual(Calculator.calculate("-2 ^ 2")?.copyText, "-4")
    XCTAssertEqual(Calculator.calculate("2 ^ -2")?.copyText, "0.25")
    XCTAssertEqual(Calculator.calculate("15% of 80")?.copyText, "12")
    XCTAssertEqual(Calculator.calculate("sqrt(81) + abs(-3)")?.copyText, "12")
    XCTAssertNil(Calculator.calculate("1 / 0"))
    XCTAssertNil(Calculator.calculate("search the web"))
  }

  func testCalculatorConvertsCompatibleUnits() {
    XCTAssertEqual(Calculator.calculate("10 km in mi")?.copyText, "6.2137119224 mi")
    XCTAssertEqual(Calculator.calculate("32 f to c")?.copyText, "0 °C")
    XCTAssertEqual(Calculator.calculate("1 gb in mib")?.copyText, "953.6743164062 MiB")
    XCTAssertNil(Calculator.calculate("10 kg in mi"))
  }

  func testQuicklinkRequestResolvesQueriesURLsAndPaths() {
    let links = [
      Quicklink(name: "github", destination: "https://github.com/search?q={query}"),
      Quicklink(name: "project", destination: "~/Documents/code/prompt"),
    ]

    let search = QuicklinkRequest(input: "GITHUB swift & appkit", quicklinks: links)
    XCTAssertEqual(search?.query, "swift & appkit")
    XCTAssertEqual(
      search?.resolvedDestination,
      .url(URL(string: "https://github.com/search?q=swift%20%26%20appkit")!)
    )
    XCTAssertNil(QuicklinkRequest(input: "github", quicklinks: links)?.resolvedDestination)

    let project = QuicklinkRequest(input: "project", quicklinks: links)
    guard case .file(let projectURL)? = project?.resolvedDestination else {
      return XCTFail("Expected a file Quicklink")
    }
    XCTAssertTrue(projectURL.path.hasSuffix("/Documents/code/prompt"))
  }

  func testSearchURLBuilder() {
    let url = URLBuilder.searchURL(
      template: "https://www.google.com/search?q={query}",
      query: "swift & appkit"
    )
    XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=swift%20%26%20appkit")
  }

  func testWebURLBuilderRecognizesFullAddresses() {
    XCTAssertEqual(URLBuilder.webURL(for: "google.com")?.absoluteString, "https://google.com")
    XCTAssertEqual(URLBuilder.webURL(for: "qz.com")?.absoluteString, "https://qz.com")
    XCTAssertEqual(
      URLBuilder.webURL(for: "example.com/path?q=river")?.absoluteString,
      "https://example.com/path?q=river"
    )
    XCTAssertEqual(
      URLBuilder.webURL(for: "http://localhost:8080/status")?.absoluteString,
      "http://localhost:8080/status"
    )
  }

  func testWebURLBuilderRejectsSearchQueriesAndUnsupportedSchemes() {
    XCTAssertNil(URLBuilder.webURL(for: "swift actors"))
    XCTAssertNil(URLBuilder.webURL(for: "not a domain.com"))
    XCTAssertNil(URLBuilder.webURL(for: "example"))
    XCTAssertNil(URLBuilder.webURL(for: "example.c"))
    XCTAssertNil(URLBuilder.webURL(for: "ftp://example.com"))
    XCTAssertNil(URLBuilder.webURL(for: "person@example.com"))
  }

  func testChatGPTRequestParsing() {
    XCTAssertEqual(
      ChatGPTRequest(input: "ai explain swift actors"),
      ChatGPTRequest(surface: .chat, query: "explain swift actors")
    )
    XCTAssertEqual(
      ChatGPTRequest(input: "WORK   plan tomorrow  "),
      ChatGPTRequest(surface: .work, query: "plan tomorrow")
    )
    XCTAssertNil(ChatGPTRequest(input: "ai"))
    XCTAssertNil(ChatGPTRequest(input: "work   "))
    XCTAssertNil(ChatGPTRequest(input: "air quality"))
  }

  func testChatGPTURLBuilder() {
    let chat = URLBuilder.chatGPTURL(
      for: ChatGPTRequest(surface: .chat, query: "swift & appkit")
    )
    let work = URLBuilder.chatGPTURL(
      for: ChatGPTRequest(surface: .work, query: "draft a plan")
    )

    XCTAssertEqual(
      chat?.absoluteString,
      "https://chatgpt.com/?q=swift%20%26%20appkit&model=gpt-5.6"
    )
    XCTAssertEqual(
      work?.absoluteString,
      "https://chatgpt.com/?q=draft%20a%20plan&model=gpt-5.6&surface=work"
    )
  }

  func testStockRequestParsing() {
    XCTAssertEqual(StockRequest(input: "stock aapl"), StockRequest(symbol: "AAPL"))
    XCTAssertEqual(StockRequest(input: " STOCK   brk-b "), StockRequest(symbol: "BRK-B"))
    XCTAssertEqual(StockRequest(input: "stock ^gspc"), StockRequest(symbol: "^GSPC"))
    XCTAssertNil(StockRequest(input: "stock"))
    XCTAssertNil(StockRequest(input: "stock apple inc"))
    XCTAssertNil(StockRequest(input: "stock ../AAPL"))
  }

  func testStockQuoteParsingAndFormatting() {
    let data = Data(
      """
      {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL",
      "fullExchangeName":"NasdaqGS","regularMarketPrice":306.605,
      "longName":"Apple Inc.","previousClose":308.26,"priceHint":2}}],"error":null}}
      """.utf8)

    let quote = StockQuote.parse(data)
    XCTAssertEqual(quote?.title, "306.61 USD  −1.66 (−0.54%)")
    XCTAssertEqual(quote?.subtitle, "Apple Inc. · AAPL · NasdaqGS")
  }

  func testStockURLsEncodeTickerPathComponents() {
    XCTAssertEqual(
      StockLookup.quoteURL(for: "^GSPC")?.absoluteString,
      "https://query2.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=1d&interval=1m"
    )
    XCTAssertEqual(
      StockLookup.quotePageURL(for: "BRK-B")?.absoluteString,
      "https://finance.yahoo.com/quote/BRK-B"
    )
  }

  func testChatGPTSubmissionPassesBrowserNameSeparatelyFromAppleScript() {
    let browser = "Browser's Custom Name"
    let arguments = Browser.chatGPTSubmitArguments(application: browser)

    XCTAssertEqual(arguments.suffix(2), ["--", browser])
    XCTAssertFalse(arguments.dropLast(2).contains(where: { $0.contains(browser) }))
    XCTAssertTrue(arguments.contains("if frontmost of process browserName then key code 36"))
  }

  func testRiverCommandParsing() {
    XCTAssertEqual(RiverCommand(input: "river restart"), .restart)
    XCTAssertEqual(RiverCommand(input: "  RIVER SETTINGS  "), .settings)
    XCTAssertNil(RiverCommand(input: "river"))
    XCTAssertNil(RiverCommand(input: "river restart now"))
  }

  func testCommandCenterIncludesBuiltInsQuicklinksAndPlugins() {
    let items = CommandCenterCatalog.items(
      query: "",
      quicklinks: [
        Quicklink(name: "github", destination: "https://github.com/search?q={query}"),
        Quicklink(name: "project", destination: "~/Documents/code/prompt"),
      ],
      pluginNames: ["weather"]
    )

    XCTAssertTrue(items.contains(where: { $0.replacement == "river settings" }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "ai " }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "stock " }))
    XCTAssertEqual(
      items.first(where: { $0.title == "github" }),
      CommandCenterItem(
        title: "github",
        subtitle: "Quicklink · https://github.com/search?q={query}",
        symbolName: "link",
        action: "Complete",
        replacement: "github ",
        submitsImmediately: false
      )
    )
    XCTAssertEqual(items.first(where: { $0.title == "project" })?.submitsImmediately, true)
    XCTAssertEqual(items.first(where: { $0.title == "/weather" })?.replacement, "/weather")
  }

  func testCommandCenterFiltersAndRanksMatches() {
    let items = CommandCenterCatalog.items(
      query: "sett",
      quicklinks: [Quicklink(name: "github", destination: "https://github.com")],
      pluginNames: ["weather"]
    )
    XCTAssertEqual(items.map(\.title), ["River Settings"])

    let pluginItems = CommandCenterCatalog.items(
      query: "weather",
      quicklinks: [],
      pluginNames: ["uv", "weather"]
    )
    XCTAssertEqual(pluginItems.first?.title, "/weather")
  }

  func testTerminalEditorPassesConfigPathSeparatelyFromScript() {
    let path = "/tmp/River's settings/config file"
    let arguments = TerminalEditor.appleScriptArguments(path: path)

    XCTAssertEqual(arguments.suffix(2), ["--", path])
    XCTAssertFalse(arguments.dropLast(2).contains(where: { $0.contains(path) }))
    XCTAssertTrue(arguments.contains("do script \"nvim \" & quoted form of item 1 of argv"))
  }

  func testSpotlightQueryTargetsFilenamesAndEscapesInput() {
    XCTAssertEqual(
      SpotlightSearch.filenamePredicate(for: "my \"file\""),
      "kMDItemFSName == \"*my \\\"file\\\"*\"cd"
    )
    XCTAssertEqual(
      SpotlightSearch.directoryPredicate(for: "my \"file\""),
      "(kMDItemFSName == \"*my \\\"file\\\"*\"cd) && (kMDItemContentType == \"public.folder\")"
    )
  }

  func testFileResultsPutDirectoriesFirstWithoutChangingOrderWithinEachGroup() {
    let results = [
      FileResult(path: "/first-file", isDirectory: false),
      FileResult(path: "/first-folder", isDirectory: true),
      FileResult(path: "/second-file", isDirectory: false),
      FileResult(path: "/second-folder", isDirectory: true),
    ]

    XCTAssertEqual(
      FileResult.directoriesFirst(results).map(\.path),
      ["/first-folder", "/second-folder", "/first-file", "/second-file"]
    )
  }

  func testPathExpansionLeavesAbsolutePathsAlone() {
    XCTAssertEqual(Paths.expand("/tmp/plugins"), "/tmp/plugins")
    XCTAssertTrue(Paths.expand("~/plugins").hasSuffix("/plugins"))
  }

  func testRestartFindsLaunchAgentPID() {
    XCTAssertEqual(
      Installer.runningPID(
        in: """
          gui/501/dev.itai.river = {
            state = running
            runs = 4
            pid = 18705
          }
          """),
      18_705
    )
    XCTAssertNil(Installer.runningPID(in: "state = waiting\n"))
  }

  func testApplicationCatalogMatchesExactlyIgnoringCase() {
    let catalog = ApplicationCatalog(applicationURLs: [
      URL(fileURLWithPath: "/Applications/Codex.app"),
      URL(fileURLWithPath: "/Applications/Google Chrome.app"),
    ])

    XCTAssertEqual(catalog.exactMatch(named: "codex")?.name, "Codex")
    XCTAssertEqual(catalog.exactMatch(named: "CODEX")?.url.path, "/Applications/Codex.app")
    XCTAssertNil(catalog.exactMatch(named: "code"))
  }

  func testApplicationCatalogFuzzyMatchesAndRanksPrefixFirst() {
    let catalog = ApplicationCatalog(applicationURLs: [
      URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
      URL(fileURLWithPath: "/Applications/Codex.app"),
      URL(fileURLWithPath: "/Applications/Xcode.app"),
    ])

    XCTAssertEqual(catalog.matches("code", limit: 2).map(\.name), ["Codex", "Xcode"])
    XCTAssertEqual(catalog.matches("vsc", limit: 3).map(\.name), ["Visual Studio Code"])
  }

  func testApplicationCatalogPromotesLearnedResultButPreservesExactMatch() {
    let catalog = ApplicationCatalog(applicationURLs: [
      URL(fileURLWithPath: "/Applications/Code.app"),
      URL(fileURLWithPath: "/Applications/Codex.app"),
    ])
    let codexIdentifier = "application:/Applications/Codex.app"

    XCTAssertEqual(
      catalog.matches("cod", limit: 2, preferredIdentifiers: [codexIdentifier]).map(\.name),
      ["Codex", "Code"]
    )
    XCTAssertEqual(
      catalog.matches("code", limit: 2, preferredIdentifiers: [codexIdentifier]).map(\.name),
      ["Code", "Codex"]
    )
  }

  func testResultKnowledgeLearnsRelearnsAndPersists() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-knowledge-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let path = directory.appendingPathComponent("knowledge.json").path
    var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
    let knowledge = ResultKnowledge(path: path, now: { currentDate })

    for _ in 0..<10 {
      knowledge.record(query: "  Có  ", itemIdentifier: "application:Code")
      currentDate.addTimeInterval(1)
    }
    for _ in 0..<3 {
      knowledge.record(query: "co", itemIdentifier: "application:Codex")
      currentDate.addTimeInterval(1)
    }

    XCTAssertEqual(
      knowledge.rankedItemIdentifiers(for: " CO "),
      ["application:Codex", "application:Code"]
    )
    XCTAssertEqual(
      knowledge.ordered(
        ["application:Code", "application:Chrome", "application:Codex"],
        for: "co",
        itemIdentifier: { $0 }
      ),
      ["application:Codex", "application:Code", "application:Chrome"]
    )

    let reloaded = ResultKnowledge(path: path, now: { currentDate })
    XCTAssertEqual(
      reloaded.rankedItemIdentifiers(for: "co"),
      ["application:Codex", "application:Code"]
    )
  }

  func testResultKnowledgeExpiresAfterFourWeeks() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-knowledge-expiry-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var currentDate = Date(timeIntervalSince1970: 2_000_000_000)
    let knowledge = ResultKnowledge(
      path: directory.appendingPathComponent("knowledge.json").path,
      now: { currentDate }
    )
    knowledge.record(query: "c", itemIdentifier: "application:Calculator")
    currentDate.addTimeInterval(29 * 24 * 60 * 60)

    XCTAssertTrue(knowledge.rankedItemIdentifiers(for: "c").isEmpty)
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
    XCTAssertEqual(runner.matchingPlugins(prefix: "he", in: directory.path), ["hello"])
    XCTAssertEqual(runner.matchingPlugins(prefix: "WE", in: directory.path), [])

    let finished = expectation(description: "plugin finished")
    runner.run(PluginRequest(input: "/hello friend")!, config: config) { output in
      XCTAssertEqual(output, "hello friend")
      finished.fulfill()
    }
    // Process startup can be delayed by macOS executable scanning on a busy machine.
    // Keep the XCTest allowance beyond River's own five-second plugin timeout.
    wait(for: [finished], timeout: 7)
  }

  func testVerbosePluginOutputDoesNotBlockTheProcess() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-verbose-plugin-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pluginURL = directory.appendingPathComponent("verbose")
    try "#!/bin/sh\nyes x | head -c 131072\n".write(
      to: pluginURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pluginURL.path)

    var config = AppConfig()
    config.pluginDirectory = directory.path
    config.pluginTimeoutMilliseconds = 2_000

    let finished = expectation(description: "verbose plugin finished")
    let runner = PluginRunner()
    runner.run(PluginRequest(input: "/verbose")!, config: config) { output in
      XCTAssertGreaterThan(output.utf8.count, 100_000)
      finished.fulfill()
    }
    wait(for: [finished], timeout: 4)
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
