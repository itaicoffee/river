import AppKit
import CoreServices
import Darwin
import Foundation

struct FileResult: Equatable {
  let path: String
  let isDirectory: Bool

  init(path: String) {
    var directoryFlag = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directoryFlag)
    self.init(path: path, isDirectory: exists && directoryFlag.boolValue)
  }

  init(path: String, isDirectory: Bool) {
    self.path = path
    self.isDirectory = isDirectory
  }

  var title: String { URL(fileURLWithPath: path).lastPathComponent }

  var knowledgeIdentifier: String {
    "file:" + URL(fileURLWithPath: path).standardizedFileURL.path
  }

  var subtitle: String {
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }

  static func directoriesFirst(_ results: [FileResult]) -> [FileResult] {
    results.filter(\.isDirectory) + results.filter { !$0.isDirectory }
  }
}

enum RiverCommand: Equatable {
  case restart
  case settings

  init?(input: String) {
    switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "river restart": self = .restart
    case "river settings": self = .settings
    default: return nil
    }
  }
}

struct CommandCenterItem: Equatable {
  let title: String
  let subtitle: String
  let symbolName: String
  let action: String
  let replacement: String
  let submitsImmediately: Bool
}

enum CommandCenterCatalog {
  static func items(
    query: String,
    quicklinks: [Quicklink],
    pluginNames: [String]
  ) -> [CommandCenterItem] {
    let builtIns = [
      CommandCenterItem(
        title: "River Settings",
        subtitle: "River · Edit the live configuration",
        symbolName: "slider.horizontal.3",
        action: "Open",
        replacement: "river settings",
        submitsImmediately: true
      ),
      CommandCenterItem(
        title: "Restart River",
        subtitle: "River · Reload the launcher and configuration",
        symbolName: "arrow.clockwise",
        action: "Restart",
        replacement: "river restart",
        submitsImmediately: true
      ),
      CommandCenterItem(
        title: "Ask ChatGPT",
        subtitle: "Input · Start a ChatGPT query",
        symbolName: "sparkles",
        action: "Complete",
        replacement: "ai ",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "Work in ChatGPT",
        subtitle: "Input · Start a ChatGPT Work query",
        symbolName: "briefcase",
        action: "Complete",
        replacement: "work ",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "Search Files",
        subtitle: "Input · Find files with Spotlight",
        symbolName: "doc.text.magnifyingglass",
        action: "Complete",
        replacement: "'",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "Define a Word",
        subtitle: "Input · Look up a Dictionary definition",
        symbolName: "character.book.closed",
        action: "Complete",
        replacement: "define ",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "Find an Emoji",
        subtitle: "Input · Fuzzy search and copy an emoji",
        symbolName: "face.smiling",
        action: "Complete",
        replacement: "emoji ",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "I'm Feeling Lucky",
        subtitle: "Input · Open Google's first result",
        symbolName: "wand.and.stars",
        action: "Complete",
        replacement: "lk ",
        submitsImmediately: false
      ),
      CommandCenterItem(
        title: "Stock Quote",
        subtitle: "Input · Look up a ticker live",
        symbolName: "chart.line.uptrend.xyaxis",
        action: "Complete",
        replacement: "stock ",
        submitsImmediately: false
      ),
    ]

    let quicklinkItems = quicklinks.map { quicklink in
      CommandCenterItem(
        title: quicklink.name,
        subtitle: "Quicklink · \(quicklink.destination)",
        symbolName: quicklink.requiresQuery ? "link" : "arrow.up.right.square",
        action: quicklink.requiresQuery ? "Complete" : "Open",
        replacement: quicklink.name + (quicklink.requiresQuery ? " " : ""),
        submitsImmediately: !quicklink.requiresQuery
      )
    }
    let pluginItems = pluginNames.map { name in
      CommandCenterItem(
        title: "/\(name)",
        subtitle: "Plugin · Executable command",
        symbolName: "terminal",
        action: "Run",
        replacement: "/\(name)",
        submitsImmediately: false
      )
    }
    let catalog = builtIns + quicklinkItems + pluginItems
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else { return catalog }

    return
      catalog.enumerated().compactMap { index, item -> (CommandCenterItem, Int, Int)? in
        guard let score = matchScore(item, query: normalizedQuery) else { return nil }
        return (item, score, index)
      }.sorted { left, right in
        left.1 == right.1 ? left.2 < right.2 : left.1 > right.1
      }.map(\.0)
  }

  private static func matchScore(_ item: CommandCenterItem, query: String) -> Int? {
    let title = normalize(item.title)
    let replacement = normalize(item.replacement)
    let searchable = normalize("\(item.title) \(item.subtitle) \(item.replacement)")

    if title == query || replacement == query { return 1_000 }
    if title.hasPrefix(query) || replacement.hasPrefix(query) { return 900 }
    if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 800 }
    if title.contains(query) { return 700 }
    let terms = query.split(whereSeparator: { $0.isWhitespace })
    if terms.allSatisfy({ searchable.contains($0) }) { return 600 }
    if isSubsequence(query, of: title) { return 500 }
    return nil
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }

  private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
    var remaining = query[...]
    for character in candidate where !remaining.isEmpty {
      if character == remaining.first { remaining.removeFirst() }
    }
    return remaining.isEmpty
  }
}

struct ChatGPTRequest: Equatable {
  enum Surface: Equatable {
    case chat
    case work
  }

  let surface: Surface
  let query: String

  init(surface: Surface, query: String) {
    self.surface = surface
    self.query = query
  }

  init?(input: String) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercased = trimmed.lowercased()
    let prefix: String

    if lowercased.hasPrefix("ai ") {
      surface = .chat
      prefix = "ai "
    } else if lowercased.hasPrefix("work ") {
      surface = .work
      prefix = "work "
    } else {
      return nil
    }

    query = String(trimmed.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return nil }
  }
}

struct StockRequest: Equatable {
  let symbol: String

  init(symbol: String) {
    self.symbol = symbol.uppercased()
  }

  init?(input: String) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let pieces = trimmed.split(whereSeparator: { $0.isWhitespace })
    guard pieces.count == 2,
      pieces[0].caseInsensitiveCompare("stock") == .orderedSame
    else {
      return nil
    }

    let symbol = String(pieces[1])
    guard symbol.count <= 32,
      symbol.range(of: "^[A-Za-z0-9.^=_-]+$", options: .regularExpression) != nil
    else {
      return nil
    }
    self.symbol = symbol.uppercased()
  }
}

struct StockQuote: Equatable {
  let symbol: String
  let name: String
  let exchange: String?
  let currency: String?
  let price: Decimal
  let marketCap: Decimal?
  let priceHint: Int

  var title: String {
    let priceText = Self.format(price, fractionDigits: priceHint)
    let currentPrice = currency.map { "\(priceText) \($0)" } ?? priceText
    let marketCapText = marketCap.map { "\(Self.compact($0)) mkt cap" }
      ?? "Mkt cap unavailable"
    return "\(currentPrice) · \(marketCapText)"
  }

  var subtitle: String {
    [name, Self.displayName(for: exchange)].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }.joined(separator: " · ")
  }

  private static func displayName(for exchange: String?) -> String? {
    switch exchange {
    case "NasdaqGS", "NasdaqGM", "NasdaqCM": return "Nasdaq"
    default: return exchange
    }
  }

  static func parse(_ data: Data, marketCapData: Data? = nil) -> StockQuote? {
    let decoder = JSONDecoder()
    guard let meta = try? decoder.decode(ChartEnvelope.self, from: data)
      .chart.result?.first?.meta,
      let price = meta.regularMarketPrice
    else {
      return nil
    }
    let marketCap = marketCapData.flatMap {
      try? decoder.decode(MarketCapEnvelope.self, from: $0)
        .timeseries.result?.first?.trailingMarketCap?.last?.reportedValue.raw
    }

    return StockQuote(
      symbol: meta.symbol,
      name: meta.longName ?? meta.shortName ?? meta.symbol,
      exchange: meta.fullExchangeName,
      currency: meta.currency,
      price: price,
      marketCap: marketCap,
      priceHint: max(0, min(meta.priceHint ?? 2, 8))
    )
  }

  private static func compact(_ value: Decimal) -> String {
    let scale: Decimal
    let suffix: String
    if value >= 1_000_000_000_000 {
      scale = 1_000_000_000_000
      suffix = "T"
    } else if value >= 1_000_000_000 {
      scale = 1_000_000_000
      suffix = "B"
    } else if value >= 1_000_000 {
      scale = 1_000_000
      suffix = "M"
    } else if value >= 1_000 {
      scale = 1_000
      suffix = "K"
    } else {
      scale = 1
      suffix = ""
    }
    return format(value / scale, fractionDigits: suffix.isEmpty ? 0 : 2) + suffix
  }

  private static func format(_ value: Decimal, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = fractionDigits
    formatter.maximumFractionDigits = fractionDigits
    formatter.roundingMode = .halfUp
    return formatter.string(from: NSDecimalNumber(decimal: value))
      ?? NSDecimalNumber(decimal: value).stringValue
  }

  private struct ChartEnvelope: Decodable {
    let chart: Chart

    struct Chart: Decodable {
      let result: [Result]?
    }

    struct Result: Decodable {
      let meta: Meta
    }

    struct Meta: Decodable {
      let currency: String?
      let symbol: String
      let fullExchangeName: String?
      let regularMarketPrice: Decimal?
      let longName: String?
      let shortName: String?
      let priceHint: Int?
    }
  }

  private struct MarketCapEnvelope: Decodable {
    let timeseries: TimeSeries

    struct TimeSeries: Decodable {
      let result: [Result]?
    }

    struct Result: Decodable {
      let trailingMarketCap: [Point]?
    }

    struct Point: Decodable {
      let reportedValue: ReportedValue
    }

    struct ReportedValue: Decodable {
      let raw: Decimal
    }
  }
}

private final class StockResponseParts {
  private let lock = NSLock()
  private var priceData: Data?
  private var marketCapData: Data?

  func setPriceData(_ data: Data?) {
    lock.lock()
    priceData = data
    lock.unlock()
  }

  func setMarketCapData(_ data: Data?) {
    lock.lock()
    marketCapData = data
    lock.unlock()
  }

  func snapshot() -> (price: Data?, marketCap: Data?) {
    lock.lock()
    defer { lock.unlock() }
    return (priceData, marketCapData)
  }
}

final class StockLookup {
  private let session: URLSession
  private var generation = 0
  private var pendingWorkItem: DispatchWorkItem?
  private var activeTasks: [URLSessionDataTask] = []

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetch(_ request: StockRequest, completion: @escaping (StockQuote?) -> Void) {
    cancel()
    let requestedGeneration = generation
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, requestedGeneration == self.generation,
        let quoteURL = Self.quoteURL(for: request.symbol),
        let marketCapURL = Self.marketCapURL(for: request.symbol)
      else {
        return
      }

      self.pendingWorkItem = nil
      let group = DispatchGroup()
      let parts = StockResponseParts()
      func dataTask(for url: URL, store: @escaping (Data?) -> Void) -> URLSessionDataTask {
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 6
        urlRequest.setValue("River/1.0", forHTTPHeaderField: "User-Agent")
        group.enter()
        return self.session.dataTask(with: urlRequest) { data, response, error in
          let status = (response as? HTTPURLResponse)?.statusCode
          store(error == nil && status == 200 ? data : nil)
          group.leave()
        }
      }

      let quoteTask = dataTask(for: quoteURL, store: parts.setPriceData)
      let marketCapTask = dataTask(for: marketCapURL, store: parts.setMarketCapData)
      self.activeTasks = [quoteTask, marketCapTask]
      self.activeTasks.forEach { $0.resume() }
      group.notify(queue: .main) { [weak self] in
        guard let self, requestedGeneration == self.generation else { return }
        self.activeTasks = []
        let data = parts.snapshot()
        let quote = data.price.flatMap {
          StockQuote.parse($0, marketCapData: data.marketCap)
        }
        completion(quote)
      }
    }
    pendingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
  }

  func cancel() {
    generation += 1
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
    activeTasks.forEach { $0.cancel() }
    activeTasks = []
  }

  static func quoteURL(for symbol: String) -> URL? {
    let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: pathCharacters)
    else {
      return nil
    }
    return URL(
      string: "https://query2.finance.yahoo.com/v8/finance/chart/\(encodedSymbol)"
        + "?range=1d&interval=1m")
  }

  static func marketCapURL(for symbol: String, now: Date = Date()) -> URL? {
    let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: pathCharacters)
    else {
      return nil
    }
    let day: TimeInterval = 24 * 60 * 60
    let period1 = Int(now.addingTimeInterval(-45 * day).timeIntervalSince1970)
    let period2 = Int(now.addingTimeInterval(day).timeIntervalSince1970)
    return URL(
      string: "https://query2.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/"
        + "timeseries/\(encodedSymbol)?symbol=\(encodedSymbol)&type=trailingMarketCap"
        + "&period1=\(period1)&period2=\(period2)")
  }

  static func quotePageURL(for symbol: String) -> URL? {
    let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: pathCharacters)
    else {
      return nil
    }
    return URL(string: "https://finance.yahoo.com/quote/\(encodedSymbol)")
  }
}

struct QuicklinkRequest: Equatable {
  let quicklink: Quicklink
  let query: String

  init?(input: String, quicklinks: [Quicklink]) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let pieces = trimmed.split(
      maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
    guard let name = pieces.first,
      let quicklink = quicklinks.first(where: {
        $0.name.caseInsensitiveCompare(String(name)) == .orderedSame
      })
    else { return nil }

    self.quicklink = quicklink
    query =
      pieces.count == 2
      ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      : ""
  }

  var resolvedDestination: QuicklinkDestination? {
    QuicklinkDestination(quicklink: quicklink, query: query)
  }
}

enum QuicklinkDestination: Equatable {
  case url(URL)
  case file(URL)

  init?(quicklink: Quicklink, query: String) {
    if quicklink.requiresQuery && query.isEmpty { return nil }

    let destination = quicklink.destination
    if destination == "~" || destination.hasPrefix("~/") || destination.hasPrefix("/") {
      guard !quicklink.requiresQuery else { return nil }
      self = .file(URL(fileURLWithPath: Paths.expand(destination)))
      return
    }

    let resolved: String
    if quicklink.requiresQuery {
      let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
      let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
      resolved = destination.replacingOccurrences(of: "{query}", with: encoded)
    } else {
      resolved = destination
    }

    guard let url = URL(string: resolved), url.scheme != nil else { return nil }
    self = .url(url)
  }

  var displayValue: String {
    switch self {
    case .url(let url): return url.absoluteString
    case .file(let url): return url.path
    }
  }
}

struct ApplicationResult: Equatable {
  let name: String
  let url: URL

  var knowledgeIdentifier: String { "application:" + url.standardizedFileURL.path }

  var subtitle: String {
    let path = url.path
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }
}

final class ApplicationCatalog {
  private struct IndexedApplication {
    let result: ApplicationResult
    let normalizedName: String
  }

  private let applications: [IndexedApplication]
  private let exactMatches: [String: ApplicationResult]

  init(applicationURLs: [URL]? = nil) {
    let urls = applicationURLs ?? Self.discoverApplicationURLs()
    var seenPaths = Set<String>()
    var indexedApplications: [IndexedApplication] = []
    var exactMatches: [String: ApplicationResult] = [:]
    indexedApplications.reserveCapacity(urls.count)

    for url in urls {
      let standardized = url.standardizedFileURL
      guard standardized.pathExtension.lowercased() == "app",
        seenPaths.insert(standardized.path).inserted
      else { continue }

      let result = ApplicationResult(
        name: standardized.deletingPathExtension().lastPathComponent, url: standardized
      )
      let normalizedName = Self.normalized(result.name)
      indexedApplications.append(
        IndexedApplication(result: result, normalizedName: normalizedName)
      )
      if exactMatches[normalizedName] == nil { exactMatches[normalizedName] = result }
    }

    applications = indexedApplications
    self.exactMatches = exactMatches
  }

  func exactMatch(named query: String) -> ApplicationResult? {
    exactMatches[Self.normalized(query)]
  }

  func matches(
    _ query: String, limit: Int, preferredIdentifiers: [String] = []
  ) -> [ApplicationResult] {
    let normalizedQuery = Self.normalized(query)
    guard !normalizedQuery.isEmpty, limit > 0 else { return [] }
    let preferredOrder = Dictionary(
      uniqueKeysWithValues: preferredIdentifiers.enumerated().map { ($0.element, $0.offset) })

    return
      applications
      .compactMap { application -> (IndexedApplication, Int)? in
        guard
          let score = Self.fuzzyScore(
            query: normalizedQuery,
            candidate: application.normalizedName
          )
        else { return nil }
        return (application, score)
      }
      .sorted {
        let leftIsExact = $0.1 == 10_000
        let rightIsExact = $1.1 == 10_000
        if leftIsExact != rightIsExact { return leftIsExact }

        let leftPreferred = preferredOrder[$0.0.result.knowledgeIdentifier]
        let rightPreferred = preferredOrder[$1.0.result.knowledgeIdentifier]
        switch (leftPreferred, rightPreferred) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }

        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.result.name.localizedCaseInsensitiveCompare($1.0.result.name)
          == .orderedAscending
      }
      .prefix(limit)
      .map(\.0.result)
  }

  static func fuzzyScore(query: String, candidate: String) -> Int? {
    guard !query.isEmpty, !candidate.isEmpty else { return nil }
    if query == candidate { return 10_000 }
    if candidate.hasPrefix(query) { return 8_000 - candidate.count }
    if let range = candidate.range(of: query) {
      return 6_000 - candidate.distance(from: candidate.startIndex, to: range.lowerBound) * 10
        - candidate.count
    }

    var queryIndex = query.startIndex
    var previousMatch: String.Index?
    var score = 0
    for candidateIndex in candidate.indices where queryIndex < query.endIndex {
      guard candidate[candidateIndex] == query[queryIndex] else { continue }
      score += 20
      if let previousMatch, candidate.index(after: previousMatch) == candidateIndex {
        score += 15
      }
      if candidateIndex == candidate.startIndex
        || candidate[candidate.index(before: candidateIndex)] == " "
        || candidate[candidate.index(before: candidateIndex)] == "-"
      {
        score += 10
      }
      previousMatch = candidateIndex
      query.formIndex(after: &queryIndex)
    }

    guard queryIndex == query.endIndex else { return nil }
    return score - candidate.count
  }

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }

  private static func discoverApplicationURLs() -> [URL] {
    let fileManager = FileManager.default
    let roots = [
      URL(fileURLWithPath: Paths.expand("~/Applications"), isDirectory: true),
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
    ]

    return roots.flatMap { root -> [URL] in
      guard
        let enumerator = fileManager.enumerator(
          at: root,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else { return [] }
      return enumerator.compactMap { $0 as? URL }.filter {
        $0.pathExtension.lowercased() == "app"
      }
    }
  }
}

final class SpotlightSearch {
  private let queue = DispatchQueue(label: "river.spotlight", qos: .userInitiated)
  private let stateLock = NSLock()
  private var generation = 0
  private var activeProcesses: [Process] = []

  func search(_ query: String, limit: Int, completion: @escaping ([FileResult]) -> Void) {
    let requestedGeneration = beginRequest()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      completion([])
      return
    }

    queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
      guard let self, self.isCurrent(requestedGeneration) else { return }

      do {
        // Spotlight does not rank folders ahead of files. Reserve a separate folder
        // query so a common name cannot push every matching folder past `head`.
        guard
          let directoryPaths = try self.paths(
            matching: Self.directoryPredicate(for: trimmed),
            limit: limit,
            generation: requestedGeneration
          ),
          let otherPaths = try self.paths(
            matching: Self.filenamePredicate(for: trimmed),
            limit: limit,
            generation: requestedGeneration
          )
        else { return }

        var seen = Set<String>()
        let paths = (directoryPaths + otherPaths).filter { seen.insert($0).inserted }
        let results = FileResult.directoriesFirst(paths.map(FileResult.init(path:)))

        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(requestedGeneration) else { return }
          completion(results)
        }
      } catch {
        self.clearProcesses(for: requestedGeneration)
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(requestedGeneration) else { return }
          completion([])
        }
      }
    }
  }

  func cancel() {
    _ = beginRequest()
  }

  private func beginRequest() -> Int {
    stateLock.lock()
    generation += 1
    let requestedGeneration = generation
    let processes = activeProcesses
    activeProcesses = []
    stateLock.unlock()
    Self.terminate(processes)
    return requestedGeneration
  }

  private func isCurrent(_ requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return requestedGeneration == generation
  }

  private func register(_ processes: [Process], for requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return false }
    activeProcesses = processes
    return true
  }

  private func clearProcesses(for requestedGeneration: Int) {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return }
    activeProcesses = []
  }

  private static func terminate(_ processes: [Process]) {
    for process in processes where process.isRunning {
      process.terminate()
    }
  }

  private func paths(
    matching predicate: String,
    limit: Int,
    generation requestedGeneration: Int
  ) throws -> [String]? {
    let spotlight = Process()
    spotlight.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    spotlight.arguments = [predicate]

    let head = Process()
    head.executableURL = URL(fileURLWithPath: "/usr/bin/head")
    head.arguments = ["-n", String(limit)]

    let link = Pipe()
    let output = Pipe()
    spotlight.standardOutput = link
    spotlight.standardError = FileHandle.nullDevice
    head.standardInput = link
    head.standardOutput = output
    head.standardError = FileHandle.nullDevice

    do {
      try spotlight.run()
      try head.run()
    } catch {
      Self.terminate([spotlight, head])
      throw error
    }
    guard register([spotlight, head], for: requestedGeneration) else {
      Self.terminate([spotlight, head])
      return nil
    }

    // Drain while `head` is running. Waiting first can fill the pipe buffer and
    // deadlock on searches that return many long paths.
    let data = output.fileHandleForReading.readDataToEndOfFile()
    head.waitUntilExit()
    if spotlight.isRunning { spotlight.terminate() }
    clearProcesses(for: requestedGeneration)

    guard isCurrent(requestedGeneration) else { return nil }
    return
      String(data: data, encoding: .utf8)?
      .split(whereSeparator: { $0.isNewline })
      .map(String.init) ?? []
  }

  static func filenamePredicate(for query: String) -> String {
    let escaped =
      query
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "kMDItemFSName == \"*\(escaped)*\"cd"
  }

  static func directoryPredicate(for query: String) -> String {
    "(\(filenamePredicate(for: query))) && (kMDItemContentType == \"public.folder\")"
  }
}

struct PluginRequest: Equatable {
  let name: String
  let arguments: [String]

  init(name: String, arguments: [String]) {
    self.name = name
    self.arguments = arguments
  }

  init?(input: String) {
    guard input.hasPrefix("/") else { return nil }
    let pieces = input.dropFirst().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let name = pieces.first,
      !name.isEmpty,
      name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    else {
      return nil
    }
    self.name = name
    self.arguments = Array(pieces.dropFirst())
  }
}

final class PluginRunner {
  private let queue = DispatchQueue(label: "river.plugins", qos: .userInitiated)
  private let stateLock = NSLock()
  private var generation = 0
  private var activeProcess: Process?

  func availablePlugins(in directory: String) -> [String] {
    let path = Paths.expand(directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    return names.filter { name in
      name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        && FileManager.default.isExecutableFile(atPath: path + "/" + name)
    }.sorted()
  }

  func matchingPlugins(prefix: String, in directory: String) -> [String] {
    let normalizedPrefix = prefix.lowercased()
    return availablePlugins(in: directory).filter {
      normalizedPrefix.isEmpty || $0.lowercased().hasPrefix(normalizedPrefix)
    }
  }

  func run(
    _ request: PluginRequest,
    config: AppConfig,
    environment: [String: String] = [:],
    completion: @escaping (String) -> Void
  ) {
    let requestedGeneration = beginRequest()

    queue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
      guard let self, self.isCurrent(requestedGeneration) else { return }
      let executable = Paths.expand(config.pluginDirectory) + "/" + request.name
      guard FileManager.default.isExecutableFile(atPath: executable) else {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(requestedGeneration) else { return }
          completion("Unknown command /\(request.name)")
        }
        return
      }

      let process = Process()
      let stdout = Pipe()
      let stderr = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = request.arguments
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, updated in
        updated
      }
      process.standardOutput = stdout
      process.standardError = stderr

      do {
        try process.run()
        guard self.register(process, for: requestedGeneration) else {
          process.terminate()
          return
        }
      } catch {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(requestedGeneration) else { return }
          completion("Could not run /\(request.name)")
        }
        return
      }

      // Drain both streams while the child is running. Waiting first can fill a
      // pipe buffer and make a chatty plugin appear to hang until its timeout.
      let outputCollector = PipeCollector(stdout)
      let errorCollector = PipeCollector(stderr)
      let deadline = DispatchTime.now() + .milliseconds(config.pluginTimeoutMilliseconds)
      let timedOut = process.waitUntilExit(before: deadline) == false
      if timedOut {
        Self.terminateAndWait(process)
      }

      let outputData = outputCollector.readToEnd()
      let errorData = errorCollector.readToEnd()
      self.clearProcess(for: requestedGeneration)
      if timedOut {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(requestedGeneration) else { return }
          completion("/\(request.name) timed out")
        }
        return
      }

      let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      let message =
        output?.isEmpty == false ? output! : (error?.isEmpty == false ? error! : "No output")

      DispatchQueue.main.async { [weak self] in
        guard let self, self.isCurrent(requestedGeneration) else { return }
        completion(message)
      }
    }
  }

  func cancel() {
    _ = beginRequest()
  }

  private func beginRequest() -> Int {
    stateLock.lock()
    generation += 1
    let requestedGeneration = generation
    let process = activeProcess
    activeProcess = nil
    stateLock.unlock()
    if process?.isRunning == true { process?.terminate() }
    return requestedGeneration
  }

  private func isCurrent(_ requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return requestedGeneration == generation
  }

  private func register(_ process: Process, for requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return false }
    activeProcess = process
    return true
  }

  private func clearProcess(for requestedGeneration: Int) {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return }
    activeProcess = nil
  }

  private static func terminateAndWait(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    if process.waitUntilExit(before: .now() + .milliseconds(250)) == false {
      Darwin.kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
    }
  }
}

private final class PipeCollector {
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var data = Data()
  private var finished = false

  init(_ pipe: Pipe) {
    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else {
        handle.readabilityHandler = nil
        return
      }

      let chunk = handle.availableData
      guard chunk.isEmpty else {
        self.lock.lock()
        self.data.append(chunk)
        self.lock.unlock()
        return
      }

      handle.readabilityHandler = nil
      self.lock.lock()
      let shouldLeave = !self.finished
      self.finished = true
      self.lock.unlock()
      if shouldLeave { self.group.leave() }
    }
  }

  func readToEnd() -> Data {
    group.wait()
    lock.lock()
    defer { lock.unlock() }
    return data
  }
}

extension Process {
  fileprivate func waitUntilExit(before deadline: DispatchTime) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    terminationHandler = { _ in semaphore.signal() }
    if !isRunning { return true }
    return semaphore.wait(timeout: deadline) == .success
  }
}

enum DictionaryLookup {
  static func definition(of word: String) -> String? {
    let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let range = CFRange(location: 0, length: (trimmed as NSString).length)
    return DCSCopyTextDefinition(nil, trimmed as CFString, range)?.takeRetainedValue() as String?
  }
}

enum URLBuilder {
  static func webURL(for input: String) -> URL? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !trimmed.contains(where: { $0.isWhitespace })
    else {
      return nil
    }

    let hasScheme = trimmed.range(of: "://") != nil
    let candidate = hasScheme ? trimmed : "https://" + trimmed
    guard let components = URLComponents(string: candidate),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      components.user == nil,
      components.password == nil,
      let host = components.host,
      isWebHost(host),
      let url = components.url
    else {
      return nil
    }
    return url
  }

  private static func isWebHost(_ host: String) -> Bool {
    let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !normalized.isEmpty else { return false }

    if normalized == "localhost" { return true }

    let ipv4Pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
    if ipv4Pieces.count == 4,
      ipv4Pieces.allSatisfy({ piece in
        !piece.isEmpty && piece.allSatisfy(\.isNumber) && Int(piece).map { $0 <= 255 } == true
      })
    {
      return true
    }

    if normalized.contains(":"),
      normalized.allSatisfy({ $0.isHexDigit || $0 == ":" })
    {
      return true
    }

    let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2,
      labels.allSatisfy({ label in
        !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
          && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
      }),
      let topLevelDomain = labels.last,
      topLevelDomain.count >= 2,
      topLevelDomain.allSatisfy(\.isLetter)
        || (topLevelDomain.hasPrefix("xn--") && topLevelDomain.count > 4)
    else {
      return false
    }
    return true
  }

  static func chatGPTURL(for request: ChatGPTRequest) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "chatgpt.com"
    components.path = "/"
    components.queryItems = [
      URLQueryItem(name: "q", value: request.query),
      URLQueryItem(name: "model", value: "gpt-5.6"),
    ]
    if request.surface == .work {
      components.queryItems?.append(URLQueryItem(name: "surface", value: "work"))
    }
    return components.url
  }

  static func searchURL(template: String, query: String) -> URL? {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
    let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    return URL(string: template.replacingOccurrences(of: "{query}", with: escaped))
  }

  static func googleRedirectTarget(from url: URL) -> URL? {
    guard let host = url.host?.lowercased(),
      host == "google.com" || host.hasSuffix(".google.com"),
      url.path == "/url",
      let rawTarget = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "q" })?.value,
      let target = URL(string: rawTarget),
      target.scheme == "https" || target.scheme == "http"
    else {
      return nil
    }
    return target
  }
}

final class LuckyResolver {
  private let queue = DispatchQueue(label: "river.lucky", qos: .userInitiated)
  private let stateLock = NSLock()
  private var generation = 0
  private var activeProcess: Process?

  func resolve(_ luckyURL: URL, fallbackURL: URL, completion: @escaping (URL) -> Void) {
    let requestedGeneration = beginRequest()

    queue.async { [weak self] in
      guard let self, self.isCurrent(requestedGeneration) else { return }
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      process.arguments = [
        "-sS", "-D", "-", "-o", "/dev/null", "--max-time", "5",
        "-A", "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/140 Safari/537.36",
        luckyURL.absoluteString,
      ]
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice

      var resolved = fallbackURL
      do {
        try process.run()
        guard self.register(process, for: requestedGeneration) else {
          process.terminate()
          return
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        self.clearProcess(for: requestedGeneration)
        if let headers = String(data: data, encoding: .utf8),
          let location = Self.redirectLocation(in: headers),
          let redirectURL = URL(string: location),
          let target = URLBuilder.googleRedirectTarget(from: redirectURL)
        {
          resolved = target
        }
      } catch {
        if process.isRunning { process.terminate() }
        self.clearProcess(for: requestedGeneration)
      }

      DispatchQueue.main.async { [weak self] in
        guard let self, self.isCurrent(requestedGeneration) else { return }
        completion(resolved)
      }
    }
  }

  func cancel() {
    _ = beginRequest()
  }

  private func beginRequest() -> Int {
    stateLock.lock()
    generation += 1
    let requestedGeneration = generation
    let process = activeProcess
    activeProcess = nil
    stateLock.unlock()
    if process?.isRunning == true { process?.terminate() }
    return requestedGeneration
  }

  private func isCurrent(_ requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return requestedGeneration == generation
  }

  private func register(_ process: Process, for requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return false }
    activeProcess = process
    return true
  }

  private func clearProcess(for requestedGeneration: Int) {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard requestedGeneration == generation else { return }
    activeProcess = nil
  }

  static func redirectLocation(in headers: String) -> String? {
    for line in headers.split(whereSeparator: { $0.isNewline }) {
      let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard pieces.count == 2, pieces[0].lowercased() == "location" else { continue }
      return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }
}

enum Browser {
  static func open(_ url: URL, application: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", application, url.absoluteString]
    do {
      try process.run()
    } catch {
      NSWorkspace.shared.open(url)
    }
  }

  static func openChatGPT(_ url: URL, application: String) {
    open(url, application: application)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = chatGPTSubmitArguments(application: application)
    try? process.run()
  }

  static func chatGPTSubmitArguments(application: String) -> [String] {
    [
      "-e", "on run argv",
      "-e", "delay 2",
      "-e", "set browserName to item 1 of argv",
      "-e", "tell application \"System Events\"",
      "-e", "if exists process browserName then",
      "-e", "if frontmost of process browserName then key code 36",
      "-e", "end if",
      "-e", "end tell",
      "-e", "end run",
      "--", application,
    ]
  }
}

enum TerminalEditor {
  static func openInNvim(path: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = appleScriptArguments(path: path)
    try process.run()
  }

  static func appleScriptArguments(path: String) -> [String] {
    [
      "-e", "on run argv",
      "-e", "tell application \"Terminal\"",
      "-e", "activate",
      "-e", "do script \"nvim \" & quoted form of item 1 of argv",
      "-e", "end tell",
      "-e", "end run",
      "--", path,
    ]
  }
}
