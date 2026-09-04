import XCTest

@testable import River

final class RiverTests: XCTestCase {
  func testConfigParsingAndUnknownKeys() {
    let config = AppConfig.parse(
      """
      # hello
      hotkey = cmd+space
      text_size = 32
      max_file_results = 7
      plugin_timeout_ms = 1200
      quicklink.github = https://github.com/search?q={query}
      ignored = yep
      """)

    XCTAssertEqual(config.hotkey, "cmd+space")
    XCTAssertEqual(config.textSize, 32)
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
      text_size = 100
      """)
    XCTAssertEqual(config.maxFileResults, AppConfig().maxFileResults)
    XCTAssertEqual(config.pluginTimeoutMilliseconds, AppConfig().pluginTimeoutMilliseconds)
    XCTAssertEqual(config.textSize, AppConfig.defaultTextSize)
  }

  func testConfigStorePersistsTextSizeWithoutDiscardingOtherSettings() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-config-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let path = directory.appendingPathComponent("config").path
    try "hotkey = ctrl+f\n# text_size = 99\nquicklink.docs = https://example.com\n"
      .write(toFile: path, atomically: true, encoding: .utf8)
    let store = ConfigStore(path: path)
    var observedSize: Int?
    store.onChange = { observedSize = $0.textSize }

    try store.setTextSize(30)

    let saved = try String(contentsOfFile: path, encoding: .utf8)
    XCTAssertTrue(saved.contains("hotkey = ctrl+f"))
    XCTAssertTrue(saved.contains("# text_size = 99"))
    XCTAssertTrue(saved.contains("text_size = 30"))
    XCTAssertTrue(saved.contains("quicklink.docs = https://example.com"))
    XCTAssertEqual(store.value.textSize, 30)
    XCTAssertEqual(observedSize, 30)
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

  func testAHDLookupURLsUseTheDocumentedQueryParameters() {
    XCTAssertEqual(
      AHDLookup.suggestionURL(for: "usef")?.absoluteString,
      "https://www.ahdictionary.com/ajax/suggest.html?query=usef"
    )
    XCTAssertEqual(
      AHDLookup.definitionURL(for: "useful thing")?.absoluteString,
      "https://www.ahdictionary.com/word/search.html?q=useful%20thing"
    )
  }

  func testAHDSuggestionParsing() {
    let data = Data(
      "<suggest><term>useful</term><term> usefully </term><term>usefulness</term></suggest>"
        .utf8)

    XCTAssertEqual(
      AHDResponseParser.suggestions(from: data),
      ["useful", "usefully", "usefulness"]
    )
  }

  func testAHDDefinitionParsingUsesTheFirstSenseInsideResults() {
    let data = Data(
      """
      <html><body>
        <div class="pseg"><i>wrong</i>Outside the result container.</div>
        <div id="results"><table><tr><td>
          <div class="rtseg"><b><font color="#006595">use·ful</font></b></div>
          <div class="pseg"><i>adj.</i>
            <div class="ds-list"><b><font>1. </font></b>
              Having a beneficial use; serviceable: <font><i>a useful kitchen gadget.</i></font>
            </div>
            <div class="ds-list"><b><font>2. </font></b>Being of practical use.</div>
          </div>
        </td></tr></table></div>
      </body></html>
      """.utf8)

    XCTAssertEqual(
      AHDResponseParser.entry(from: data),
      AHDEntry(
        headword: "use·ful",
        partOfSpeech: "adj.",
        definition: "Having a beneficial use; serviceable: a useful kitchen gadget."
      )
    )
  }

  func testAHDDefinitionParsingSupportsAnUnnumberedSense() {
    let data = Data(
      """
      <html><body><div id="results">
        <div class="rtseg"><font color="#006595">maiden over</font></div>
        <div class="pseg"><i>n.</i> An over in cricket during which no runs are scored.</div>
      </div></body></html>
      """.utf8)

    XCTAssertEqual(
      AHDResponseParser.entry(from: data),
      AHDEntry(
        headword: "maiden over",
        partOfSpeech: "n.",
        definition: "An over in cricket during which no runs are scored."
      )
    )
  }

  func testAHDDefinitionParsingRejectsAMissingEntry() {
    let data = Data("<html><body><div id=\"results\">No word definition found</div></body></html>".utf8)
    XCTAssertNil(AHDResponseParser.entry(from: data))
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

  func testEmojiRequestParsing() {
    XCTAssertEqual(EmojiRequest(input: "emoji heart"), EmojiRequest(query: "heart"))
    XCTAssertEqual(EmojiRequest(input: " EMOJI   kitty  "), EmojiRequest(query: "kitty"))
    XCTAssertNil(EmojiRequest(input: "emoji"))
    XCTAssertNil(EmojiRequest(input: "emojified heart"))
  }

  func testEmojiCatalogFuzzyMatchesNamesAliasesAndFlags() {
    XCTAssertEqual(EmojiCatalog.matches("heart").first?.emoji, "❤️")
    XCTAssertEqual(EmojiCatalog.matches("hrt").first?.emoji, "❤️")
    XCTAssertEqual(EmojiCatalog.matches("kitty").first?.emoji, "🐈")
    XCTAssertEqual(EmojiCatalog.matches("slovenia").first?.emoji, "🇸🇮")
    XCTAssertTrue(EmojiCatalog.matches("woman developer").contains(where: {
      $0.emoji == "👩‍💻"
    }))
  }

  func testEmojiCatalogHonorsLimitAndRejectsEmptyQueries() {
    XCTAssertEqual(EmojiCatalog.matches("face", limit: 3).count, 3)
    XCTAssertTrue(EmojiCatalog.matches("   ").isEmpty)
    XCTAssertTrue(EmojiCatalog.matches("face", limit: 0).isEmpty)
  }

  func testStockQuoteParsingAndFormatting() {
    let quoteData = Data(
      """
      {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL",
      "fullExchangeName":"NasdaqGS","regularMarketPrice":306.605,
      "longName":"Apple Inc.","priceHint":2}}],"error":null}}
      """.utf8)
    let marketCapData = Data(
      """
      {"timeseries":{"result":[{"trailingMarketCap":[{"reportedValue":{
      "raw":4498801926800,"fmt":"4.50T"}}]}],"error":null}}
      """.utf8)

    let quote = StockQuote.parse(quoteData, marketCapData: marketCapData)
    XCTAssertEqual(quote?.title, "307 USD · 4.5T mkt cap")
    XCTAssertEqual(quote?.subtitle, "Apple Inc. · Nasdaq")

    let lowPriceData = Data(
      """
      {"chart":{"result":[{"meta":{"currency":"USD","symbol":"SOFI",
      "fullExchangeName":"NasdaqGS","regularMarketPrice":6.425,
      "longName":"SoFi Technologies, Inc.","priceHint":2}}],"error":null}}
      """.utf8)
    let billionCapData = Data(
      """
      {"timeseries":{"result":[{"trailingMarketCap":[{"reportedValue":{
      "raw":6420000000,"fmt":"6.42B"}}]}],"error":null}}
      """.utf8)
    XCTAssertEqual(
      StockQuote.parse(lowPriceData, marketCapData: billionCapData)?.title,
      "6.43 USD · 6.4B mkt cap"
    )
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
    XCTAssertEqual(
      StockLookup.marketCapURL(
        for: "AAPL", now: Date(timeIntervalSince1970: 1_786_406_400)
      )?.absoluteString,
      "https://query2.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/"
        + "timeseries/AAPL?symbol=AAPL&type=trailingMarketCap&period1=1782518400&period2=1786492800"
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
    XCTAssertEqual(RiverCommand(input: "restart"), .restartComputer)
    XCTAssertEqual(RiverCommand(input: "  SHUT DOWN "), .shutDown)
    XCTAssertEqual(RiverCommand(input: "shutdown"), .shutDown)
    XCTAssertEqual(RiverCommand(input: "LOCK"), .lock)
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
    XCTAssertTrue(items.contains(where: { $0.replacement == "restart" }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "shut down" }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "lock" }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "ai " }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "stock " }))
    XCTAssertTrue(items.contains(where: { $0.replacement == "emoji " }))
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

  func testMacSystemActionsUseExpectedSystemEventsCommands() {
    XCTAssertTrue(MacSystemAction.restart.appleScriptArguments.contains(where: {
      $0.contains("to restart")
    }))
    XCTAssertTrue(MacSystemAction.shutDown.appleScriptArguments.contains(where: {
      $0.contains("to shut down")
    }))
    XCTAssertTrue(MacSystemAction.lock.appleScriptArguments.contains(where: {
      $0.contains("control down, command down")
    }))
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

  func testFileSearchRanksExactFolderAheadOfLooseMatches() {
    let results = [
      FileResult(path: "/Users/test/Documents/codec", isDirectory: false),
      FileResult(path: "/Users/test/Documents/code-archive", isDirectory: true),
      FileResult(path: "/Users/test/Documents/code", isDirectory: true),
      FileResult(path: "/Users/test/Documents/Xcode", isDirectory: true),
    ]

    XCTAssertEqual(
      FileSearchRanker.rank(results, query: "code", limit: 4).map(\.path),
      [
        "/Users/test/Documents/code",
        "/Users/test/Documents/code-archive",
        "/Users/test/Documents/codec",
        "/Users/test/Documents/Xcode",
      ]
    )
  }

  func testFileSearchSupportsTyposAndPathTokens() {
    let code = FileResult(path: "/Users/test/Documents/code", isDirectory: true)
    let services = FileResult(
      path: "/Users/test/Documents/code/prompt/Sources/River/Services.swift",
      isDirectory: false
    )
    let unrelated = FileResult(path: "/Users/test/Downloads/movie.mov", isDirectory: false)

    let catalog = FileSearchCatalog(
      [unrelated, code, services].map(FileSearchRanker.PreparedResult.init)
    )

    XCTAssertEqual(catalog.search("cdoe", limit: 5).first?.path, code.path)
    XCTAssertEqual(catalog.search("doc serv", limit: 5).first?.path, services.path)
    XCTAssertEqual(catalog.search("serv sw", limit: 5).first?.path, services.path)
  }

  func testFileSearchLearningBoostDoesNotOverrideExactBasename() {
    let exact = FileResult(path: "/Users/test/code", isDirectory: false)
    let learned = FileResult(path: "/Users/test/code-archive", isDirectory: true)

    XCTAssertEqual(
      FileSearchRanker.rank(
        [learned, exact],
        query: "code",
        limit: 2,
        preferredIdentifiers: [learned.knowledgeIdentifier]
      ).first?.path,
      exact.path
    )
  }

  func testLocalSearchFindsNestedFolderWhenSpotlightHasNoResults() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-local-search-\(UUID().uuidString)", isDirectory: true)
    let documents = root.appendingPathComponent("Documents", isDirectory: true)
    let code = documents.appendingPathComponent("code", isDirectory: true)
    try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let local = LocalFileSearch(
      roots: [root],
      cacheURL: root.appendingPathComponent("index.plist"),
      startImmediately: false
    )
    let spotlightDisabled = StubFileSearchProvider(results: [])
    let engine = FileSearchEngine(providers: [local, spotlightDisabled])
    let finished = expectation(description: "all file search providers finished")

    engine.search("code", limit: 5) { results, isFinal in
      guard isFinal else { return }
      XCTAssertEqual(
        URL(fileURLWithPath: results.first?.path ?? "").standardizedFileURL.path,
        code.standardizedFileURL.path
      )
      finished.fulfill()
    }
    wait(for: [finished], timeout: 2)
  }

  func testLocalSearchCompletesAnAbsolutePath() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-path-search-\(UUID().uuidString)", isDirectory: true)
    let code = root.appendingPathComponent("code", isDirectory: true)
    try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let local = LocalFileSearch(
      roots: [root],
      cacheURL: root.appendingPathComponent("index.plist"),
      startImmediately: false
    )
    let finished = expectation(description: "direct path completed")
    local.search(root.appendingPathComponent("co").path, limit: 5) { results in
      XCTAssertEqual(
        URL(fileURLWithPath: results.first?.path ?? "").standardizedFileURL.path,
        code.standardizedFileURL.path
      )
      finished.fulfill()
    }
    wait(for: [finished], timeout: 2)
  }

  func testFileSearchRanksAUsefulResultInALargeCatalog() {
    var results = (0..<20_000).map {
      FileResult(path: "/Users/test/Documents/archive/random-item-\($0).txt", isDirectory: false)
    }
    let target = FileResult(path: "/Users/test/Documents/code", isDirectory: true)
    results.append(target)
    let prepared = results.map(FileSearchRanker.PreparedResult.init)
    let catalog = FileSearchCatalog(prepared)
    let startedAt = Date()
    let ranked = catalog.search("code", limit: 5)
    let elapsed = Date().timeIntervalSince(startedAt)

    XCTAssertEqual(ranked.first?.path, target.path)
    XCTAssertLessThan(elapsed, 0.05, "Prepared search took \(elapsed) seconds")
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

  func testInstallerSeedsScheduledStatusPlugins() {
    XCTAssertEqual(
      Installer.defaultStatusPluginNames,
      [
        "010-weather.10m.zsh",
        "020-uv.15m.zsh",
        "030-watts.10s.zsh",
        "040-wifi.30s.zsh",
        "050-speedtest.30s.zsh",
      ]
    )
    XCTAssertEqual(
      Installer.defaultStatusPluginNames.compactMap {
        StatusPluginDescriptor(filename: $0, directory: "/plugins")?.displayName
      },
      ["weather", "uv", "watts", "wifi", "speedtest"]
    )
  }

  func testStatusPluginPresentationUsesLowercaseNamesAndRemovesReadablePrefix() {
    XCTAssertEqual(
      StatusPluginPresentation.readableName(for: "Codex_Context"),
      "codex context"
    )
    XCTAssertEqual(
      StatusPluginPresentation.displayValue(
        for: StatusPluginSnapshot(
          id: "codex-context",
          displayName: "codex-context",
          output: "codex context · 52% used"
        )
      ),
      "52% used"
    )
  }

  func testStatusPluginPresentationUsesMeaningfulSymbols() {
    func snapshot(_ name: String, output: String = "ready") -> StatusPluginSnapshot {
      StatusPluginSnapshot(id: name, displayName: name, output: output)
    }

    XCTAssertEqual(StatusPluginPresentation.symbolName(for: snapshot("wifi")), "wifi")
    XCTAssertEqual(
      StatusPluginPresentation.symbolName(for: snapshot("codex-context")),
      "brain.head.profile"
    )
    XCTAssertEqual(
      StatusPluginPresentation.symbolName(for: snapshot("aapl", output: "$304 / $4.5T")),
      "chart.line.uptrend.xyaxis"
    )
  }

  func testShiftModifierRevealsFileInFinder() {
    XCTAssertTrue(LauncherKeyAction.shouldRevealFile(modifierFlags: [.shift]))
    XCTAssertTrue(LauncherKeyAction.shouldRevealFile(modifierFlags: [.shift, .capsLock]))
    XCTAssertFalse(LauncherKeyAction.shouldRevealFile(modifierFlags: []))
    XCTAssertFalse(LauncherKeyAction.shouldRevealFile(modifierFlags: [.command]))
  }

  func testCommandPlusAndMinusAdjustTextSize() {
    XCTAssertEqual(
      LauncherKeyAction.textSizeAdjustment(
        modifierFlags: [.command, .shift], charactersIgnoringModifiers: "=", characters: "+"),
      2
    )
    XCTAssertEqual(
      LauncherKeyAction.textSizeAdjustment(
        modifierFlags: [.command], charactersIgnoringModifiers: "-"),
      -2
    )
    XCTAssertNil(
      LauncherKeyAction.textSizeAdjustment(
        modifierFlags: [], charactersIgnoringModifiers: "-")
    )
    XCTAssertNil(
      LauncherKeyAction.textSizeAdjustment(
        modifierFlags: [.command, .option], charactersIgnoringModifiers: "=")
    )
  }

  func testInstallerRunsFromAnIdentifiedAppBundleForLocationPermission() {
    XCTAssertEqual(
      Installer.launchAgentPropertyList["ProgramArguments"] as? [String],
      ["/usr/bin/open", "-n", "-g", Paths.installedApp, "--args", "run"]
    )
    XCTAssertNil(Installer.launchAgentPropertyList["KeepAlive"])
    XCTAssertEqual(
      Installer.appInfoPropertyList["CFBundleIdentifier"] as? String,
      "dev.itai.river"
    )
    XCTAssertNotNil(Installer.appInfoPropertyList["NSLocationUsageDescription"])
    XCTAssertNotNil(Installer.appInfoPropertyList["NSLocationWhenInUseUsageDescription"])
  }

  func testBundledWeatherUsesDynamicRiverCoordinatesInsteadOfIPGeolocation() {
    XCTAssertTrue(Installer.weatherPlugin.contains("RIVER_LATITUDE"))
    XCTAssertTrue(Installer.weatherPlugin.contains("RIVER_LONGITUDE"))
    XCTAssertFalse(Installer.weatherPlugin.contains("latitude=45.82&longitude=13.84"))
    XCTAssertTrue(Installer.weatherPlugin.contains("api.open-meteo.com"))
    XCTAssertFalse(Installer.weatherPlugin.contains("wttr.in"))
    XCTAssertTrue(Installer.legacyWeatherPlugin.contains("wttr.in"))
  }

  func testBundledUVUsesDynamicRiverCoordinatesInsteadOfIPGeolocation() {
    XCTAssertTrue(Installer.uvPlugin.contains("RIVER_LATITUDE"))
    XCTAssertTrue(Installer.uvPlugin.contains("RIVER_LONGITUDE"))
    XCTAssertFalse(Installer.uvPlugin.contains("latitude=45.82&longitude=13.84"))
    XCTAssertTrue(Installer.uvPlugin.contains("current=uv_index"))
    XCTAssertTrue(Installer.uvPlugin.contains("api.open-meteo.com"))
    XCTAssertFalse(Installer.uvPlugin.contains("wttr.in"))
    XCTAssertTrue(Installer.legacyUVPlugin.contains("wttr.in"))
  }

  func testBundledWiFiUsesLinkStateWhenSSIDIsPrivacyProtected() {
    XCTAssertTrue(Installer.wifiPlugin.contains("LinkStatusActive : TRUE"))
    XCTAssertTrue(Installer.wifiPlugin.contains("RIVER_WIFI_SSID"))
    XCTAssertTrue(Installer.wifiPlugin.contains("label=${ssid:-connected}"))
    XCTAssertFalse(Installer.wifiPlugin.contains("system_profiler"))
    XCTAssertFalse(Installer.legacyWifiPlugin.contains("LinkStatusActive : TRUE"))
  }

  func testBundledSpeedtestSupportsCurrentAndLegacyNetworkQualityOutput() {
    XCTAssertTrue(Installer.speedtestPlugin.contains("(Download|Downlink) capacity"))
    XCTAssertTrue(Installer.speedtestPlugin.contains("(Upload|Uplink) capacity"))
    XCTAssertTrue(Installer.speedtestPlugin.contains("LinkStatusActive : TRUE"))
    XCTAssertTrue(Installer.speedtestPlugin.contains("networkQuality -s -M 20 >"))
    XCTAssertFalse(Installer.speedtestPlugin.contains(" -I "))
    XCTAssertFalse(Installer.speedtestPlugin.contains("system_profiler"))
    XCTAssertTrue(Installer.speedtestPlugin.contains("status: active"))
    XCTAssertTrue(Installer.legacySpeedtestPlugin.contains("/Download capacity/"))
  }

  func testRiverLocationFormatsPluginEnvironmentAndMovementThreshold() {
    let original = RiverLocation(latitude: 45.82345, longitude: 13.84456, updatedAt: .distantPast)
    XCTAssertEqual(original.pluginEnvironment["RIVER_LATITUDE"], "45.823450")
    XCTAssertEqual(original.pluginEnvironment["RIVER_LONGITUDE"], "13.844560")
    XCTAssertTrue(original.isNear(
      RiverLocation(latitude: 45.8239, longitude: 13.8449, updatedAt: .distantFuture)))
    XCTAssertFalse(original.isNear(
      RiverLocation(latitude: 45.9, longitude: 13.9, updatedAt: .distantFuture)))
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

  func testSystemSettingsCatalogMatchesPaneNamesAndNativeSearchTerms() {
    let displays = SystemSettingsResult(
      name: "Displays",
      identifier: "com.apple.Displays-Settings.extension",
      searchTerms: ["Screen Resolution", "monitors", "Night Shift"]
    )
    let sound = SystemSettingsResult(
      name: "Sound",
      identifier: "com.apple.Sound-Settings.extension",
      searchTerms: ["output volume", "speakers"]
    )
    let catalog = SystemSettingsCatalog(results: [sound, displays])

    XCTAssertEqual(catalog.exactMatch(named: "DISPLAYS"), displays)
    XCTAssertEqual(catalog.matches("display", limit: 5).first, displays)
    XCTAssertEqual(catalog.matches("resolution", limit: 5).first, displays)
    XCTAssertEqual(catalog.matches("speakers", limit: 5).first, sound)
    XCTAssertEqual(
      catalog.matches(
        "displays", limit: 5, preferredIdentifiers: [sound.knowledgeIdentifier]
      ).first,
      displays
    )
    XCTAssertEqual(
      displays.url?.absoluteString,
      "x-apple.systempreferences:com.apple.Displays-Settings.extension"
    )
  }

  func testSystemSettingsCatalogDiscoversTheNativeDisplaysPane() throws {
    let displays = try XCTUnwrap(SystemSettingsCatalog().exactMatch(named: "displays"))
    XCTAssertEqual(displays.name, "Displays")
    XCTAssertTrue(displays.identifier.lowercased().contains("displays"))
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
    try "max_file_results = 3\n".write(to: configURL, atomically: true, encoding: .utf8)
    let store = ConfigStore(path: configURL.path)
    XCTAssertEqual(store.value.maxFileResults, 3)

    let reloaded = expectation(description: "config reloaded")
    store.onChange = { config in
      if config.maxFileResults == 7 { reloaded.fulfill() }
    }
    store.startWatching()
    try "max_file_results = 7\n".write(to: configURL, atomically: true, encoding: .utf8)

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

  func testStatusPluginFilenamesParseRefreshIntervals() {
    XCTAssertEqual(
      StatusPluginDescriptor(filename: "weather.10m.zsh", directory: "/plugins")?.interval,
      10 * 60
    )
    XCTAssertEqual(
      StatusPluginDescriptor(filename: "010-watts.5s", directory: "/plugins")?.displayName,
      "watts"
    )
    XCTAssertEqual(
      StatusPluginDescriptor(filename: "uv.2h.sh", directory: "/plugins")?.path,
      "/plugins/uv.2h.sh"
    )
    XCTAssertNil(StatusPluginDescriptor(filename: "weather.zsh", directory: "/plugins"))
    XCTAssertNil(StatusPluginDescriptor(filename: "weather.1s.zsh", directory: "/plugins"))
    XCTAssertNil(StatusPluginDescriptor(filename: "weather.8d.zsh", directory: "/plugins"))
  }

  func testStatusPluginOutputUsesFirstNonemptyLineAndBoundsInput() {
    XCTAssertEqual(
      StatusPluginOutput.firstLine(from: Data("\n  Weather 18°C  \nTomorrow\n".utf8)),
      "Weather 18°C"
    )
    XCTAssertNil(StatusPluginOutput.firstLine(from: Data(" \n\t\n".utf8)))
    let oversized = Data((String(repeating: "x", count: StatusPluginOutput.maximumBytes + 100)).utf8)
    XCTAssertEqual(
      StatusPluginOutput.firstLine(from: oversized)?.utf8.count,
      StatusPluginOutput.maximumBytes
    )
  }

  func testStatusPluginsRunInBackgroundAndPublishCachedOutput() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-status-plugin-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pluginURL = directory.appendingPathComponent("weather.5s.sh")
    try "#!/bin/sh\nprintf '\\n18°C\\nignored\\n'\n".write(
      to: pluginURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pluginURL.path)

    var config = AppConfig()
    config.pluginDirectory = directory.path
    config.pluginTimeoutMilliseconds = 1_000
    let manager = StatusPluginManager(
      cachePath: directory.appendingPathComponent("cache/status.json").path)
    let refreshed = expectation(description: "status plugin refreshed")
    manager.onChange = { snapshots in
      if snapshots.first?.output == "18°C" { refreshed.fulfill() }
    }
    manager.start(config: config)
    defer { manager.stop() }

    XCTAssertEqual(manager.snapshots.first?.displayText, "weather …")
    wait(for: [refreshed], timeout: 3)
    XCTAssertEqual(manager.snapshots.first?.displayText, "18°C")

    manager.stop()
    let reloaded = StatusPluginManager(
      cachePath: directory.appendingPathComponent("cache/status.json").path)
    reloaded.start(config: config)
    XCTAssertEqual(reloaded.snapshots.first?.displayText, "18°C")
    reloaded.stop()
  }

  func testScheduledPluginIsNotAnInteractiveSlashCommand() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("river-status-plugin-catalog-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for name in ["weather", "weather.10m.zsh"] {
      let url = directory.appendingPathComponent(name)
      try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    XCTAssertEqual(PluginRunner().availablePlugins(in: directory.path), ["weather"])
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

private final class StubFileSearchProvider: FileSearchProviding {
  let results: [FileResult]

  init(results: [FileResult]) {
    self.results = results
  }

  func search(_ query: String, limit: Int, completion: @escaping ([FileResult]) -> Void) {
    completion(Array(results.prefix(limit)))
  }

  func cancel() {}
}
