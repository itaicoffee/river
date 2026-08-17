import Foundation

protocol FileSearchProviding: AnyObject {
  func search(_ query: String, limit: Int, completion: @escaping ([FileResult]) -> Void)
  func cancel()
}

enum FileSearchRanker {
  struct PreparedResult {
    let result: FileResult
    let standardizedPath: String
    let normalizedName: String
    let normalizedPath: String
    let pathComponents: [String]
    let nameTerms: [String]
    let pathTerms: [String]
    let searchTerms: [String]

    init(_ result: FileResult) {
      self.result = result
      standardizedPath = URL(fileURLWithPath: result.path).standardizedFileURL.path
      normalizedName = FileSearchRanker.normalize(result.title)
      normalizedPath = FileSearchRanker.normalize(FileSearchRanker.displayPath(standardizedPath))
      pathComponents = normalizedPath.split(separator: "/").map(String.init)
      nameTerms = FileSearchRanker.terms(in: normalizedName)
      pathTerms = pathComponents.dropLast().flatMap(FileSearchRanker.terms(in:))
      searchTerms = Array(Set(nameTerms + pathTerms))
    }
  }

  private struct RankedResult {
    let result: FileResult
    let score: Int
  }

  static func rank(
    _ results: [FileResult],
    query: String,
    limit: Int,
    preferredIdentifiers: [String] = []
  ) -> [FileResult] {
    rankPrepared(
      results.map(PreparedResult.init),
      query: query,
      limit: limit,
      preferredIdentifiers: preferredIdentifiers
    )
  }

  static func rankPrepared(
    _ results: [PreparedResult],
    query: String,
    limit: Int,
    preferredIdentifiers: [String] = []
  ) -> [FileResult] {
    guard limit > 0 else { return [] }
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else { return [] }

    let queryTokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace || $0 == "/" })
      .map(String.init)
    guard !queryTokens.isEmpty else { return [] }

    let preferredOrder = Dictionary(
      uniqueKeysWithValues: preferredIdentifiers.enumerated().map { ($0.element, $0.offset) })
    var seen = Set<String>()

    return results.compactMap { prepared -> RankedResult? in
      let result = prepared.result
      guard seen.insert(prepared.standardizedPath).inserted else { return nil }
      guard
        let matchScore = score(
          query: normalizedQuery,
          tokens: queryTokens,
          name: prepared.normalizedName,
          path: prepared.normalizedPath,
          nameTerms: prepared.nameTerms,
          pathTerms: prepared.pathTerms
        )
      else { return nil }

      var score = matchScore
      if result.isDirectory { score += 240 }
      score -= max(0, prepared.pathComponents.count - 2) * 8
      if let preference = preferredOrder[result.knowledgeIdentifier] {
        score += max(900, 2_400 - preference * 200)
      }
      return RankedResult(result: result, score: score)
    }
    .sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.result.isDirectory != $1.result.isDirectory { return $0.result.isDirectory }
      if $0.result.title.count != $1.result.title.count {
        return $0.result.title.count < $1.result.title.count
      }
      return $0.result.path.localizedCaseInsensitiveCompare($1.result.path) == .orderedAscending
    }
    .prefix(limit)
    .map(\.result)
  }

  private static func score(
    query: String,
    tokens: [String],
    name: String,
    path: String,
    nameTerms: [String],
    pathTerms: [String]
  ) -> Int? {
    if query == path { return 22_000 }
    if (query.hasPrefix("~") || query.hasPrefix("/")), path.hasPrefix(query) {
      return 18_000 - path.count
    }
    if query == name { return 20_000 }
    if name.hasPrefix(query) { return 17_000 - name.count }
    if let range = name.range(of: query) {
      let offset = name.distance(from: name.startIndex, to: range.lowerBound)
      return 14_000 - offset * 20 - name.count
    }
    if query.contains("/"), let range = path.range(of: query) {
      let offset = path.distance(from: path.startIndex, to: range.lowerBound)
      return 13_000 - min(offset, 200) * 4
    }

    var total = 0
    var basenameMatches = 0
    for token in tokens {
      var best = nameTerms.compactMap { componentScore(token, candidate: $0) }.max()
      if best != nil { basenameMatches += 1 }

      for term in pathTerms {
        if let componentMatch = componentScore(token, candidate: term) {
          best = max(best ?? Int.min, componentMatch - 650)
        }
      }
      guard let best else { return nil }
      total += best
    }

    if tokens.count > 1 {
      total += 1_500
      if basenameMatches == tokens.count { total += 800 }
    }
    return total
  }

  private static func componentScore(_ query: String, candidate: String) -> Int? {
    guard !query.isEmpty, !candidate.isEmpty else { return nil }
    if query == candidate { return 6_000 }
    if candidate.hasPrefix(query) { return 5_200 - min(candidate.count, 200) }

    if let range = candidate.range(of: query) {
      let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
      return 4_400 - offset * 15 - min(candidate.count, 200)
    }

    if query.count >= 3,
      abs(query.count - candidate.count) <= allowedEditDistance(for: query),
      damerauLevenshtein(query, candidate, maximum: allowedEditDistance(for: query))
        <= allowedEditDistance(for: query)
    {
      return 3_800 - abs(query.count - candidate.count) * 100
    }

    guard query.count >= 3, let subsequence = subsequenceScore(query, candidate: candidate) else {
      return nil
    }
    return 2_700 + subsequence
  }

  private static func subsequenceScore(_ query: String, candidate: String) -> Int? {
    var queryIndex = query.startIndex
    var previousMatch: String.Index?
    var firstMatchOffset: Int?
    var lastMatchOffset = 0
    var boundaryMatches = 0
    var score = 0

    for candidateIndex in candidate.indices where queryIndex < query.endIndex {
      guard candidate[candidateIndex] == query[queryIndex] else { continue }
      let offset = candidate.distance(from: candidate.startIndex, to: candidateIndex)
      if firstMatchOffset == nil { firstMatchOffset = offset }
      lastMatchOffset = offset
      score += 20
      if let previousMatch, candidate.index(after: previousMatch) == candidateIndex {
        score += 35
      }
      if candidateIndex == candidate.startIndex {
        score += 45
        boundaryMatches += 1
      } else {
        let previousCharacter = candidate[candidate.index(before: candidateIndex)]
        if !previousCharacter.isLetter && !previousCharacter.isNumber {
          score += 45
          boundaryMatches += 1
        }
      }
      previousMatch = candidateIndex
      query.formIndex(after: &queryIndex)
    }

    guard queryIndex == query.endIndex else { return nil }
    let matchSpan = lastMatchOffset - (firstMatchOffset ?? 0) + 1
    let maximumCompactSpan = max(query.count * 4, query.count + 8)
    guard matchSpan <= maximumCompactSpan || boundaryMatches == query.count else { return nil }
    return score - min(candidate.count, 200)
  }

  private static func allowedEditDistance(for query: String) -> Int {
    query.count >= 8 ? 2 : 1
  }

  // Bounded optimal-string-alignment distance. Transposed characters count as one edit.
  private static func damerauLevenshtein(
    _ left: String, _ right: String, maximum: Int
  ) -> Int {
    let left = Array(left)
    let right = Array(right)
    guard abs(left.count - right.count) <= maximum else { return maximum + 1 }
    if left == right { return 0 }

    var previousPrevious = Array(0...right.count)
    var previous = previousPrevious

    for leftIndex in 1...left.count {
      var current = Array(repeating: 0, count: right.count + 1)
      current[0] = leftIndex
      var rowMinimum = current[0]

      for rightIndex in 1...right.count {
        let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
        current[rightIndex] = min(
          current[rightIndex - 1] + 1,
          previous[rightIndex] + 1,
          previous[rightIndex - 1] + substitutionCost
        )
        if leftIndex > 1, rightIndex > 1,
          left[leftIndex - 1] == right[rightIndex - 2],
          left[leftIndex - 2] == right[rightIndex - 1]
        {
          current[rightIndex] = min(current[rightIndex], previousPrevious[rightIndex - 2] + 1)
        }
        rowMinimum = min(rowMinimum, current[rightIndex])
      }

      if rowMinimum > maximum { return maximum + 1 }
      previousPrevious = previous
      previous = current
    }
    return previous[right.count]
  }

  static func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
  }

  private static func terms(in text: String) -> [String] {
    let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    return words.count == 1 && words.first == text ? [text] : [text] + words
  }

  private static func displayPath(_ path: String) -> String {
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }
}

struct FileSearchCatalog {
  private struct FuzzyKey: Hashable {
    let first: Character
    let length: Int
  }

  private static let maximumQueryCandidates = 6_000

  let entries: [FileSearchRanker.PreparedResult]
  private let trigramPostings: [String: [Int]]
  private let firstCharacterPostings: [Character: [Int]]
  private let fuzzyPostings: [FuzzyKey: [Int]]

  init(_ entries: [FileSearchRanker.PreparedResult]) {
    self.entries = entries
    var trigramPostings: [String: [Int]] = [:]
    var firstCharacterPostings: [Character: [Int]] = [:]
    var fuzzyPostings: [FuzzyKey: [Int]] = [:]

    for (index, entry) in entries.enumerated() {
      var entryTrigrams = Set<String>()
      var entryFirstCharacters = Set<Character>()
      var entryFuzzyKeys = Set<FuzzyKey>()
      for term in entry.searchTerms where !term.isEmpty {
        let characters = Array(term)
        if let first = characters.first {
          entryFirstCharacters.insert(first)
          entryFuzzyKeys.insert(FuzzyKey(first: first, length: characters.count))
        }
        entryTrigrams.formUnion(Self.trigrams(in: characters))
      }
      for trigram in entryTrigrams { trigramPostings[trigram, default: []].append(index) }
      for first in entryFirstCharacters {
        firstCharacterPostings[first, default: []].append(index)
      }
      for key in entryFuzzyKeys { fuzzyPostings[key, default: []].append(index) }
    }

    self.trigramPostings = trigramPostings
    self.firstCharacterPostings = firstCharacterPostings
    self.fuzzyPostings = fuzzyPostings
  }

  func search(
    _ query: String,
    limit: Int,
    preferredIdentifiers: [String] = []
  ) -> [FileResult] {
    let normalized = FileSearchRanker.normalize(query)
    let tokens = normalized.split(whereSeparator: { $0.isWhitespace || $0 == "/" })
      .map(String.init)
    guard !tokens.isEmpty else { return [] }

    var candidates: Set<Int>?
    for token in tokens {
      let tokenCandidates = candidateIndices(for: token)
      if let existing = candidates {
        candidates = existing.intersection(tokenCandidates)
      } else {
        candidates = tokenCandidates
      }
      if candidates?.isEmpty == true { return [] }
    }

    let selected: [FileSearchRanker.PreparedResult]
    if let candidates, candidates.count > Self.maximumQueryCandidates {
      var bounded: [FileSearchRanker.PreparedResult] = []
      bounded.reserveCapacity(Self.maximumQueryCandidates)
      for (index, entry) in entries.enumerated() where candidates.contains(index) {
        bounded.append(entry)
        if bounded.count == Self.maximumQueryCandidates { break }
      }
      selected = bounded
    } else {
      selected = (candidates ?? []).map { entries[$0] }
    }
    return FileSearchRanker.rankPrepared(
      selected,
      query: normalized,
      limit: limit,
      preferredIdentifiers: preferredIdentifiers
    )
  }

  private func candidateIndices(for token: String) -> Set<Int> {
    let characters = Array(token)
    guard let first = characters.first else { return [] }
    var candidates = Set<Int>()

    let tokenTrigrams = Self.trigrams(in: characters)
    if !tokenTrigrams.isEmpty {
      let postings = tokenTrigrams.compactMap { trigramPostings[$0] }
      if postings.count == tokenTrigrams.count,
        let smallest = postings.min(by: { $0.count < $1.count })
      {
        var contiguous = Set(smallest)
        for posting in postings where posting.count != smallest.count || posting != smallest {
          contiguous.formIntersection(posting)
        }
        candidates.formUnion(contiguous)
      }
    }

    let editDistance = characters.count >= 8 ? 2 : 1
    for length in max(1, characters.count - editDistance)...(characters.count + editDistance) {
      candidates.formUnion(fuzzyPostings[FuzzyKey(first: first, length: length)] ?? [])
    }

    if candidates.isEmpty || candidates.count < 200 {
      candidates.formUnion(firstCharacterPostings[first]?.prefix(2_000) ?? [])
    }
    return candidates
  }

  private static func trigrams(in characters: [Character]) -> [String] {
    guard characters.count >= 3 else { return [] }
    return (0...(characters.count - 3)).map {
      String(characters[$0...($0 + 2)])
    }
  }
}

final class LocalFileSearch: FileSearchProviding {
  private struct StoredEntry: Codable {
    let path: String
    let isDirectory: Bool
  }

  private struct Snapshot: Codable {
    let version: Int
    let roots: [String]
    let entries: [StoredEntry]
  }

  private static let snapshotVersion = 1
  private static let maximumEntries = 250_000
  private static let refreshInterval: TimeInterval = 5 * 60
  private static let ignoredDirectoryNames: Set<String> = [
    ".build", ".cache", ".git", ".svn", ".trash", "deriveddata", "node_modules",
  ]

  private let roots: [URL]
  private let cacheURL: URL
  private let fileManager: FileManager
  private let maintenanceQueue = DispatchQueue(label: "river.file-index", qos: .utility)
  private let queryQueue = DispatchQueue(
    label: "river.file-search", qos: .userInitiated, attributes: .concurrent)
  private let stateLock = NSLock()
  private var catalog = FileSearchCatalog([])
  private var generation = 0
  private var started = false
  private var isScanning = false
  private var lastScanAt = Date.distantPast

  init(
    roots: [URL] = [URL(fileURLWithPath: Paths.homeDirectory, isDirectory: true)],
    cacheURL: URL = URL(fileURLWithPath: Paths.fileSearchIndexFile),
    fileManager: FileManager = .default,
    startImmediately: Bool = true
  ) {
    var seen = Set<String>()
    self.roots = roots.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    self.cacheURL = cacheURL
    self.fileManager = fileManager
    if startImmediately { start() }
  }

  func start() {
    stateLock.lock()
    guard !started else {
      stateLock.unlock()
      return
    }
    started = true
    isScanning = true
    stateLock.unlock()

    maintenanceQueue.async { [weak self] in
      guard let self else { return }
      self.loadSnapshot()
      self.rebuildIndex()
    }
  }

  func search(_ query: String, limit: Int, completion: @escaping ([FileResult]) -> Void) {
    let requestedGeneration = beginRequest()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, limit > 0 else {
      completion([])
      return
    }
    refreshIfNeeded()

    stateLock.lock()
    let snapshot = catalog
    stateLock.unlock()

    queryQueue.async { [weak self] in
      guard let self, self.isCurrent(requestedGeneration) else { return }
      let direct = self.directPathCandidates(for: trimmed)
      let shallow = self.shallowCandidates()
      let indexed = snapshot.search(trimmed, limit: limit)
      let results = FileSearchRanker.rank(
        direct + shallow + indexed,
        query: trimmed,
        limit: limit
      )
      DispatchQueue.main.async { [weak self] in
        guard let self, self.isCurrent(requestedGeneration) else { return }
        completion(results)
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
    stateLock.unlock()
    return requestedGeneration
  }

  private func isCurrent(_ requestedGeneration: Int) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return generation == requestedGeneration
  }

  private func refreshIfNeeded() {
    stateLock.lock()
    let shouldRefresh = started && !isScanning
      && Date().timeIntervalSince(lastScanAt) >= Self.refreshInterval
    if shouldRefresh { isScanning = true }
    stateLock.unlock()
    guard shouldRefresh else { return }
    maintenanceQueue.async { [weak self] in self?.rebuildIndex() }
  }

  private func loadSnapshot() {
    guard let data = try? Data(contentsOf: cacheURL),
      let snapshot = try? PropertyListDecoder().decode(Snapshot.self, from: data),
      snapshot.version == Self.snapshotVersion,
      snapshot.roots == roots.map(\.path)
    else { return }

    let loaded = snapshot.entries.compactMap { entry -> FileSearchRanker.PreparedResult? in
      guard fileManager.fileExists(atPath: entry.path) else { return nil }
      return FileSearchRanker.PreparedResult(
        FileResult(path: entry.path, isDirectory: entry.isDirectory)
      )
    }
    let loadedCatalog = FileSearchCatalog(loaded)
    stateLock.lock()
    catalog = loadedCatalog
    stateLock.unlock()
  }

  private func rebuildIndex() {
    var discovered: [FileSearchRanker.PreparedResult] = []
    stateLock.lock()
    let previousCount = catalog.entries.count
    stateLock.unlock()
    discovered.reserveCapacity(min(previousCount, Self.maximumEntries))

    for root in roots where discovered.count < Self.maximumEntries {
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
      ) else { continue }

      while let url = enumerator.nextObject() as? URL {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectory = values?.isDirectory == true
        if isDirectory, shouldIgnoreDirectory(url, root: root) {
          enumerator.skipDescendants()
          continue
        }
        discovered.append(
          FileSearchRanker.PreparedResult(
            FileResult(path: url.path, isDirectory: isDirectory)
          )
        )
        if discovered.count >= Self.maximumEntries { break }
      }
    }

    let rebuiltCatalog = FileSearchCatalog(discovered)
    stateLock.lock()
    catalog = rebuiltCatalog
    lastScanAt = Date()
    isScanning = false
    stateLock.unlock()
    persist(discovered)
  }

  private func persist(_ results: [FileSearchRanker.PreparedResult]) {
    let snapshot = Snapshot(
      version: Self.snapshotVersion,
      roots: roots.map(\.path),
      entries: results.map {
        StoredEntry(path: $0.result.path, isDirectory: $0.result.isDirectory)
      }
    )
    guard let data = try? PropertyListEncoder.binary.encode(snapshot) else { return }
    do {
      try fileManager.createDirectory(
        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: cacheURL, options: .atomic)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    } catch {}
  }

  private func directPathCandidates(for query: String) -> [FileResult] {
    guard query.hasPrefix("/") || query.hasPrefix("~") else { return [] }
    let expanded = Paths.expand(query)
    let url = URL(fileURLWithPath: expanded)
    let directoryURL: URL
    let partialName: String
    if query.hasSuffix("/") {
      directoryURL = url
      partialName = ""
    } else {
      directoryURL = url.deletingLastPathComponent()
      partialName = url.lastPathComponent
    }

    var candidates = contents(of: directoryURL).filter {
      partialName.isEmpty
        || FileSearchRanker.normalize($0.title).contains(FileSearchRanker.normalize(partialName))
        || FileSearchRanker.rank([$0], query: partialName, limit: 1).isEmpty == false
    }
    var isDirectory = ObjCBool(false)
    if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) {
      candidates.append(FileResult(path: expanded, isDirectory: isDirectory.boolValue))
    }
    return candidates
  }

  private func shallowCandidates() -> [FileResult] {
    var candidates: [FileResult] = []
    for root in roots {
      let firstLevel = contents(of: root)
      candidates.append(contentsOf: firstLevel)
      for candidate in firstLevel where candidate.isDirectory {
        let url = URL(fileURLWithPath: candidate.path, isDirectory: true)
        guard !shouldIgnoreDirectory(url, root: root) else { continue }
        candidates.append(contentsOf: contents(of: url))
      }
    }
    return candidates
  }

  private func contents(of directory: URL) -> [FileResult] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
    guard let urls = try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    else { return [] }
    return urls.map { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return FileResult(path: url.path, isDirectory: values?.isDirectory == true)
    }
  }

  private func shouldIgnoreDirectory(_ url: URL, root: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    if Self.ignoredDirectoryNames.contains(name) { return true }
    return name == "library" && url.deletingLastPathComponent().standardizedFileURL == root
  }
}

final class FileSearchEngine {
  private final class Session {
    let query: String
    let limit: Int
    let preferredIdentifiers: [String]
    let completion: ([FileResult], Bool) -> Void
    var resultsByPath: [String: FileResult] = [:]
    var completedProviders = 0
    var lastPublished: [FileResult] = []

    init(
      query: String,
      limit: Int,
      preferredIdentifiers: [String],
      completion: @escaping ([FileResult], Bool) -> Void
    ) {
      self.query = query
      self.limit = limit
      self.preferredIdentifiers = preferredIdentifiers
      self.completion = completion
    }
  }

  private let providers: [FileSearchProviding]
  private var currentSession: Session?

  init(providers: [FileSearchProviding] = [LocalFileSearch(), SpotlightSearch()]) {
    self.providers = providers
  }

  func search(
    _ query: String,
    limit: Int,
    preferredIdentifiers: [String] = [],
    completion: @escaping ([FileResult], Bool) -> Void
  ) {
    cancel()
    let session = Session(
      query: query,
      limit: limit,
      preferredIdentifiers: preferredIdentifiers,
      completion: completion
    )
    currentSession = session
    guard !providers.isEmpty else {
      completion([], true)
      return
    }

    let candidateLimit = max(100, limit * 20)
    for provider in providers {
      provider.search(query, limit: candidateLimit) { [weak self, weak session] results in
        let publish = {
          guard let self, let session, self.currentSession === session else { return }
          for result in results {
            session.resultsByPath[result.path] = result
          }
          session.completedProviders += 1
          let ranked = FileSearchRanker.rank(
            Array(session.resultsByPath.values),
            query: session.query,
            limit: session.limit,
            preferredIdentifiers: session.preferredIdentifiers
          )
          let isFinal = session.completedProviders == self.providers.count
          if ranked != session.lastPublished || isFinal {
            session.lastPublished = ranked
            session.completion(ranked, isFinal)
          }
        }
        if Thread.isMainThread { publish() } else { DispatchQueue.main.async(execute: publish) }
      }
    }
  }

  func cancel() {
    currentSession = nil
    providers.forEach { $0.cancel() }
  }
}

private extension PropertyListEncoder {
  static var binary: PropertyListEncoder {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return encoder
  }
}
