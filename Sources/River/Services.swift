import AppKit
import CoreServices
import Foundation

struct FileResult: Equatable {
  let path: String

  var title: String { URL(fileURLWithPath: path).lastPathComponent }

  var knowledgeIdentifier: String {
    "file:" + URL(fileURLWithPath: path).standardizedFileURL.path
  }

  var subtitle: String {
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
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
  private let applications: [ApplicationResult]

  init(applicationURLs: [URL]? = nil) {
    let urls = applicationURLs ?? Self.discoverApplicationURLs()
    var seenPaths = Set<String>()
    applications = urls.compactMap { url in
      let standardized = url.standardizedFileURL
      guard standardized.pathExtension.lowercased() == "app",
        seenPaths.insert(standardized.path).inserted
      else { return nil }

      return ApplicationResult(
        name: standardized.deletingPathExtension().lastPathComponent,
        url: standardized
      )
    }
  }

  func exactMatch(named query: String) -> ApplicationResult? {
    let normalizedQuery = Self.normalized(query)
    return applications.first { Self.normalized($0.name) == normalizedQuery }
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
      .compactMap { application -> (ApplicationResult, Int)? in
        guard
          let score = Self.fuzzyScore(
            query: normalizedQuery,
            candidate: Self.normalized(application.name)
          )
        else { return nil }
        return (application, score)
      }
      .sorted {
        let leftIsExact = $0.1 == 10_000
        let rightIsExact = $1.1 == 10_000
        if leftIsExact != rightIsExact { return leftIsExact }

        let leftPreferred = preferredOrder[$0.0.knowledgeIdentifier]
        let rightPreferred = preferredOrder[$1.0.knowledgeIdentifier]
        switch (leftPreferred, rightPreferred) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }

        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
      }
      .prefix(limit)
      .map(\.0)
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
  private var generation = 0

  func search(_ query: String, limit: Int, completion: @escaping ([FileResult]) -> Void) {
    generation += 1
    let requestedGeneration = generation
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      completion([])
      return
    }

    queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
      guard let self, requestedGeneration == self.generation else { return }

      let spotlight = Process()
      spotlight.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
      spotlight.arguments = [Self.filenamePredicate(for: trimmed)]

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
        head.waitUntilExit()
        if spotlight.isRunning { spotlight.terminate() }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let paths =
          String(data: data, encoding: .utf8)?
          .split(whereSeparator: { $0.isNewline })
          .map(String.init) ?? []
        let results = paths.map(FileResult.init(path:))

        DispatchQueue.main.async { [weak self] in
          guard let self, requestedGeneration == self.generation else { return }
          completion(results)
        }
      } catch {
        DispatchQueue.main.async { completion([]) }
      }
    }
  }

  func cancel() {
    generation += 1
  }

  static func filenamePredicate(for query: String) -> String {
    let escaped =
      query
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "kMDItemFSName == \"*\(escaped)*\"cd"
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
  private var generation = 0

  func availablePlugins(in directory: String) -> [String] {
    let path = Paths.expand(directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    return names.filter { name in
      !name.hasPrefix(".") && FileManager.default.isExecutableFile(atPath: path + "/" + name)
    }.sorted()
  }

  func matchingPlugins(prefix: String, in directory: String) -> [String] {
    availablePlugins(in: directory).filter {
      prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased())
    }
  }

  func run(_ request: PluginRequest, config: AppConfig, completion: @escaping (String) -> Void) {
    generation += 1
    let requestedGeneration = generation

    queue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
      guard let self, requestedGeneration == self.generation else { return }
      let executable = Paths.expand(config.pluginDirectory) + "/" + request.name
      guard FileManager.default.isExecutableFile(atPath: executable) else {
        DispatchQueue.main.async { completion("Unknown command /\(request.name)") }
        return
      }

      let process = Process()
      let stdout = Pipe()
      let stderr = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = request.arguments
      process.standardOutput = stdout
      process.standardError = stderr

      do {
        try process.run()
      } catch {
        DispatchQueue.main.async { completion("Could not run /\(request.name)") }
        return
      }

      let deadline = DispatchTime.now() + .milliseconds(config.pluginTimeoutMilliseconds)
      if process.waitUntilExit(before: deadline) == false {
        process.terminate()
        DispatchQueue.main.async { [weak self] in
          guard let self, requestedGeneration == self.generation else { return }
          completion("/\(request.name) timed out")
        }
        return
      }

      let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
      let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      let message =
        output?.isEmpty == false ? output! : (error?.isEmpty == false ? error! : "No output")

      DispatchQueue.main.async { [weak self] in
        guard let self, requestedGeneration == self.generation else { return }
        completion(message)
      }
    }
  }

  func cancel() {
    generation += 1
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
  private var generation = 0

  func resolve(_ luckyURL: URL, fallbackURL: URL, completion: @escaping (URL) -> Void) {
    generation += 1
    let requestedGeneration = generation

    queue.async { [weak self] in
      guard let self, requestedGeneration == self.generation else { return }
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
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if let headers = String(data: data, encoding: .utf8),
          let location = Self.redirectLocation(in: headers),
          let redirectURL = URL(string: location),
          let target = URLBuilder.googleRedirectTarget(from: redirectURL)
        {
          resolved = target
        }
      } catch {}

      DispatchQueue.main.async { [weak self] in
        guard let self, requestedGeneration == self.generation else { return }
        completion(resolved)
      }
    }
  }

  func cancel() {
    generation += 1
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
