import Foundation

final class ResultKnowledge {
  private struct Selection: Codable {
    let query: String
    let itemIdentifier: String
    let selectedAt: Date
  }

  private struct Database: Codable {
    let version: Int
    var selections: [Selection]
  }

  private struct Rank {
    var count = 0
    var lastSelectedAt = Date.distantPast
  }

  private static let retentionInterval: TimeInterval = 28 * 24 * 60 * 60
  private static let maximumSelectionCount = 2_000

  private let path: String
  private let now: () -> Date
  private var selections: [Selection]
  private var rankedIdentifiersByQuery: [String: [String]] = [:]
  private var nextExpiration = Date.distantFuture

  init(path: String = Paths.knowledgeFile, now: @escaping () -> Date = Date.init) {
    self.path = path
    self.now = now

    if let data = FileManager.default.contents(atPath: path),
      let database = try? JSONDecoder().decode(Database.self, from: data),
      database.version == 1
    {
      selections = database.selections
    } else {
      selections = []
    }
    prune(at: now())
  }

  func record(query: String, itemIdentifier: String) {
    let normalizedQuery = Self.normalizedQuery(query)
    guard !normalizedQuery.isEmpty, !itemIdentifier.isEmpty else { return }

    let selectedAt = now()
    selections.append(
      Selection(
        query: normalizedQuery,
        itemIdentifier: itemIdentifier,
        selectedAt: selectedAt
      ))
    rankedIdentifiersByQuery.removeValue(forKey: normalizedQuery)
    prune(at: selectedAt)
    persist()
  }

  func rankedItemIdentifiers(for query: String) -> [String] {
    let normalizedQuery = Self.normalizedQuery(query)
    guard !normalizedQuery.isEmpty else { return [] }
    pruneIfNeeded()
    if let cached = rankedIdentifiersByQuery[normalizedQuery] { return cached }

    var ranks: [String: Rank] = [:]
    for selection in selections where selection.query == normalizedQuery {
      var rank = ranks[selection.itemIdentifier] ?? Rank()
      // Three deliberate choices are enough to replace a long-standing preference.
      rank.count = min(rank.count + 1, 3)
      rank.lastSelectedAt = max(rank.lastSelectedAt, selection.selectedAt)
      ranks[selection.itemIdentifier] = rank
    }

    let identifiers = ranks.keys.sorted { left, right in
      guard let leftRank = ranks[left], let rightRank = ranks[right] else { return left < right }
      if leftRank.count != rightRank.count { return leftRank.count > rightRank.count }
      if leftRank.lastSelectedAt != rightRank.lastSelectedAt {
        return leftRank.lastSelectedAt > rightRank.lastSelectedAt
      }
      return left < right
    }
    rankedIdentifiersByQuery[normalizedQuery] = identifiers
    return identifiers
  }

  func hasPreference(for query: String, itemIdentifier: String) -> Bool {
    rankedItemIdentifiers(for: query).contains(itemIdentifier)
  }

  func ordered<Match>(
    _ matches: [Match], for query: String, itemIdentifier: (Match) -> String
  ) -> [Match] {
    let preferredIdentifiers = rankedItemIdentifiers(for: query)
    guard !preferredIdentifiers.isEmpty else { return matches }
    let preferredOrder = Dictionary(
      uniqueKeysWithValues: preferredIdentifiers.enumerated().map { ($0.element, $0.offset) })

    return matches.enumerated().sorted { left, right in
      let leftOrder = preferredOrder[itemIdentifier(left.element)]
      let rightOrder = preferredOrder[itemIdentifier(right.element)]
      switch (leftOrder, rightOrder) {
      case let (left?, right?) where left != right: return left < right
      case (_?, nil): return true
      case (nil, _?): return false
      default: return left.offset < right.offset
      }
    }.map(\.element)
  }

  static func normalizedQuery(_ query: String) -> String {
    query
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
  }

  private func pruneIfNeeded() {
    let currentDate = now()
    if currentDate > nextExpiration { prune(at: currentDate) }
  }

  private func prune(at currentDate: Date) {
    let originalCount = selections.count
    let cutoff = currentDate.addingTimeInterval(-Self.retentionInterval)
    selections.removeAll { $0.selectedAt < cutoff }
    if selections.count > Self.maximumSelectionCount {
      selections = Array(
        selections.sorted { $0.selectedAt > $1.selectedAt }
          .prefix(Self.maximumSelectionCount)
          .reversed()
      )
    }
    if selections.count != originalCount { rankedIdentifiersByQuery.removeAll() }
    nextExpiration =
      selections.map { $0.selectedAt.addingTimeInterval(Self.retentionInterval) }.min()
      ?? .distantFuture
  }

  private func persist() {
    let url = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(Database(version: 1, selections: selections))
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      // Ranking is opportunistic; launching a result must still work if persistence fails.
    }
  }
}
