import Foundation

struct SystemSettingsResult: Equatable {
  let name: String
  let identifier: String
  let searchTerms: [String]

  var knowledgeIdentifier: String { "system-setting:" + identifier }

  var url: URL? {
    URL(string: "x-apple.systempreferences:\(identifier)")
  }
}

final class SystemSettingsCatalog {
  private struct IndexedSetting {
    let result: SystemSettingsResult
    let normalizedName: String
    let normalizedSearchTerms: [String]
  }

  private let settings: [IndexedSetting]

  init(results: [SystemSettingsResult]? = nil) {
    let results = results ?? Self.discoverSettings()
    settings = results.map { result in
      IndexedSetting(
        result: result,
        normalizedName: Self.normalized(result.name),
        normalizedSearchTerms: result.searchTerms.map(Self.normalized)
      )
    }
  }

  func exactMatch(named query: String) -> SystemSettingsResult? {
    let query = Self.normalized(query)
    return settings.first(where: { $0.normalizedName == query })?.result
  }

  func matches(
    _ query: String, limit: Int, preferredIdentifiers: [String] = []
  ) -> [SystemSettingsResult] {
    let query = Self.normalized(query)
    guard !query.isEmpty, limit > 0 else { return [] }
    let preferredOrder = Dictionary(
      uniqueKeysWithValues: preferredIdentifiers.enumerated().map { ($0.element, $0.offset) })

    return settings.compactMap { setting -> (IndexedSetting, Int)? in
      var bestScore = ApplicationCatalog.fuzzyScore(
        query: query, candidate: setting.normalizedName
      ).map { $0 + 2_000 }

      for term in setting.normalizedSearchTerms {
        guard let score = Self.searchTermScore(query: query, term: term) else { continue }
        bestScore = max(bestScore ?? Int.min, score)
      }
      guard let bestScore else { return nil }
      return (setting, bestScore)
    }
    .sorted {
      let leftIsExact = $0.0.normalizedName == query
      let rightIsExact = $1.0.normalizedName == query
      if leftIsExact != rightIsExact { return leftIsExact }

      let leftPreferred = preferredOrder[$0.0.result.knowledgeIdentifier]
      let rightPreferred = preferredOrder[$1.0.result.knowledgeIdentifier]
      switch (leftPreferred, rightPreferred) {
      case (let left?, let right?) where left != right: return left < right
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

  private static func searchTermScore(query: String, term: String) -> Int? {
    if query == term { return 9_000 }
    if term.hasPrefix(query) { return 7_000 - term.count }
    if let range = term.range(of: query) {
      return 5_000 - term.distance(from: term.startIndex, to: range.lowerBound) * 10
        - term.count
    }
    return ApplicationCatalog.fuzzyScore(query: query, candidate: term).map { $0 - 2_000 }
  }

  private static func discoverSettings() -> [SystemSettingsResult] {
    let roots = [
      "/System/Library/ExtensionKit/Extensions",
      "/Library/ExtensionKit/Extensions",
      Paths.expand("~/Library/ExtensionKit/Extensions"),
    ]
    var seenIdentifiers = Set<String>()
    var discovered: [SystemSettingsResult] = []

    for root in roots {
      guard
        let urls = try? FileManager.default.contentsOfDirectory(
          at: URL(fileURLWithPath: root),
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      else { continue }

      for url in urls {
        guard let bundle = Bundle(url: url), let result = result(from: bundle),
          seenIdentifiers.insert(result.identifier).inserted
        else { continue }
        discovered.append(result)
      }
    }

    return discovered.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private static func result(from bundle: Bundle) -> SystemSettingsResult? {
    guard
      let attributes = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
      attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
      let settingsAttributes = attributes["SettingsExtensionAttributes"] as? [String: Any],
      settingsAttributes["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
      let identifier = bundle.bundleIdentifier,
      let name = localizedSettingName(in: bundle),
      !name.isEmpty
    else { return nil }

    let searchTerms =
      (settingsAttributes["searchTermsFileName"] as? String)
      .map { loadSearchTerms(named: $0, in: bundle) } ?? []
    return SystemSettingsResult(name: name, identifier: identifier, searchTerms: searchTerms)
  }

  private static func localizedSettingName(in bundle: Bundle) -> String? {
    let candidates = [
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
      bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
    ]
    return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
  }

  private static func loadSearchTerms(named name: String, in bundle: Bundle) -> [String] {
    guard let url = bundle.url(forResource: name, withExtension: "searchTerms"),
      let data = try? Data(contentsOf: url),
      let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return [] }

    var terms = Set<String>()
    for group in root.values {
      guard let group = group as? [String: Any],
        let strings = group["localizableStrings"] as? [[String: Any]]
      else { continue }

      for entry in strings {
        for key in ["title", "index"] {
          guard let value = entry[key] as? String else { continue }
          for term in value.split(separator: ",") {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { terms.insert(cleaned) }
          }
        }
      }
    }
    return terms.sorted()
  }

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
  }
}
