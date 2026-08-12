import Foundation

struct EmojiRequest: Equatable {
  let query: String

  init(query: String) {
    self.query = query
  }

  init?(input: String) {
    let pieces = input.trimmingCharacters(in: .whitespacesAndNewlines).split(
      maxSplits: 1,
      whereSeparator: { $0.isWhitespace }
    )
    guard pieces.count == 2,
      pieces[0].caseInsensitiveCompare("emoji") == .orderedSame
    else {
      return nil
    }

    let query = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return nil }
    self.query = query
  }
}

struct EmojiResult: Equatable {
  let emoji: String
  let name: String
  let aliases: [String]

  var copyText: String { emoji }
}

enum EmojiCatalog {
  private struct CatalogEntry {
    let result: EmojiResult
    let normalizedFields: [String]
    let words: [String]
  }

  private struct ScoredResult {
    let result: EmojiResult
    let score: Int
    let index: Int
  }

  private static let resultLimit = 50

  static func matches(_ query: String, limit: Int = resultLimit) -> [EmojiResult] {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

    return entries.enumerated().compactMap { index, entry -> ScoredResult? in
      guard let score = score(entry, for: normalizedQuery) else { return nil }
      return ScoredResult(result: entry.result, score: score, index: index)
    }.sorted { left, right in
      if left.score != right.score { return left.score > right.score }
      if left.result.name.count != right.result.name.count {
        return left.result.name.count < right.result.name.count
      }
      return left.index < right.index
    }.prefix(limit).map(\.result)
  }

  private static let entries: [CatalogEntry] = {
    var results: [CatalogEntry] = []
    var seen = Set<String>()

    func append(_ result: EmojiResult) {
      guard seen.insert(result.emoji).inserted else { return }
      let normalizedFields = ([result.name] + result.aliases).map(normalize).filter {
        !$0.isEmpty
      }
      results.append(
        CatalogEntry(
          result: result,
          normalizedFields: normalizedFields,
          words: normalizedFields.flatMap {
            $0.split(separator: " ").map(String.init)
          }
        ))
    }

    for range in emojiScalarRanges {
      for value in range {
        guard let scalar = Unicode.Scalar(value), scalar.properties.isEmoji,
          !scalar.properties.isEmojiModifier,
          !(0x1F1E6...0x1F1FF).contains(value),
          let unicodeName = scalar.properties.name
        else {
          continue
        }

        let name = commonNames[value] ?? sentenceCase(unicodeName)
        let aliases = aliases(for: value, name: name)
        let emoji = scalar.properties.isEmojiPresentation
          ? String(scalar) : String(scalar) + "\u{FE0F}"
        append(EmojiResult(emoji: emoji, name: name, aliases: aliases))

        if scalar.properties.isEmojiModifierBase {
          for tone in skinTones {
            append(
              EmojiResult(
                emoji: String(scalar) + tone.emoji,
                name: "\(name): \(tone.name) skin tone",
                aliases: aliases + [tone.name]
              ))
          }
        }
      }
    }

    for result in sequenceEntries { append(result) }
    for result in professionEntries { append(result) }
    for result in flagEntries { append(result) }
    return results
  }()

  private static let emojiScalarRanges: [ClosedRange<UInt32>] = [
    0x00A9...0x00AE,
    0x203C...0x3299,
    0x1F000...0x1FAFF,
  ]

  private static let skinTones: [(emoji: String, name: String)] = [
    ("🏻", "light"),
    ("🏼", "medium-light"),
    ("🏽", "medium"),
    ("🏾", "medium-dark"),
    ("🏿", "dark"),
  ]

  private static let commonNames: [UInt32: String] = [
    0x2600: "Sun",
    0x2601: "Cloud",
    0x2602: "Umbrella",
    0x2603: "Snowman",
    0x2615: "Hot beverage",
    0x2639: "Frowning face",
    0x263A: "Smiling face",
    0x2660: "Spade suit",
    0x2663: "Club suit",
    0x2665: "Heart suit",
    0x2666: "Diamond suit",
    0x2705: "Check mark button",
    0x2708: "Airplane",
    0x2709: "Envelope",
    0x270F: "Pencil",
    0x2714: "Check mark",
    0x2728: "Sparkles",
    0x2744: "Snowflake",
    0x2763: "Heart exclamation",
    0x2764: "Red heart",
    0x2B50: "Star",
  ]

  private static let specificAliases: [UInt32: [String]] = [
    0x2615: ["coffee", "tea", "caffeine"],
    0x2705: ["check", "done", "yes", "complete"],
    0x274C: ["cross", "no", "wrong", "cancel"],
    0x2764: ["heart", "love"],
    0x1F31F: ["star", "favorite"],
    0x1F37A: ["beer", "drink"],
    0x1F381: ["gift", "present"],
    0x1F382: ["birthday", "cake"],
    0x1F389: ["party", "celebrate", "congratulations"],
    0x1F3E0: ["home", "house"],
    0x1F408: ["cat", "kitty", "kitten"],
    0x1F431: ["cat", "kitty", "kitten"],
    0x1F436: ["dog", "puppy"],
    0x1F440: ["eyes", "look", "watching"],
    0x1F44D: ["thumbs up", "like", "approve", "yes"],
    0x1F44E: ["thumbs down", "dislike", "no"],
    0x1F44B: ["hello", "goodbye", "bye", "wave"],
    0x1F4A9: ["poop", "shit"],
    0x1F4AF: ["100", "hundred", "perfect"],
    0x1F4AA: ["strong", "strength", "flex"],
    0x1F4CC: ["pin", "pinned"],
    0x1F4CE: ["attachment", "paperclip"],
    0x1F525: ["fire", "lit", "hot"],
    0x1F50D: ["search", "find", "magnifying glass"],
    0x1F511: ["key", "password"],
    0x1F512: ["lock", "locked", "secure"],
    0x1F513: ["unlock", "unlocked"],
    0x1F595: ["middle finger"],
    0x1F602: ["laugh", "laughing", "lol", "tears of joy"],
    0x1F609: ["wink", "winking"],
    0x1F60D: ["love", "heart eyes"],
    0x1F614: ["sad", "pensive"],
    0x1F62D: ["cry", "crying", "sad", "sobbing"],
    0x1F644: ["eye roll", "eyeroll"],
    0x1F64F: ["please", "thanks", "thank you", "pray", "high five"],
    0x1F680: ["rocket", "launch", "ship"],
    0x1F6A8: ["siren", "alert", "emergency"],
    0x1F914: ["think", "thinking", "hmm"],
    0x1F91D: ["handshake", "deal", "agreement"],
    0x1F923: ["laugh", "laughing", "rofl", "lol"],
    0x1F92F: ["mind blown", "wow", "shocked"],
    0x1F970: ["love", "hearts", "affection"],
    0x1FAE0: ["melt", "melting"],
    0x1FAE1: ["salute", "saluting"],
  ]

  private static func aliases(for value: UInt32, name: String) -> [String] {
    var values = specificAliases[value] ?? []
    let words = Set(normalize(name).split(separator: " ").map(String.init))

    if words.contains("cat") { values += ["kitty", "kitten"] }
    if words.contains("dog") { values += ["puppy"] }
    if words.contains("heart") { values += ["love"] }
    if words.contains("smiling") { values += ["happy", "smile", "smiley"] }
    if words.contains("crying") || words.contains("tear") || words.contains("tears") {
      values += ["sad", "cry"]
    }
    return Array(Set(values)).sorted()
  }

  private static let sequenceEntries: [EmojiResult] = [
    EmojiResult(emoji: "#️⃣", name: "Keycap: #", aliases: ["hash", "number"]),
    EmojiResult(emoji: "*️⃣", name: "Keycap: *", aliases: ["asterisk", "star"]),
    EmojiResult(emoji: "0️⃣", name: "Keycap: 0", aliases: ["zero"]),
    EmojiResult(emoji: "1️⃣", name: "Keycap: 1", aliases: ["one"]),
    EmojiResult(emoji: "2️⃣", name: "Keycap: 2", aliases: ["two"]),
    EmojiResult(emoji: "3️⃣", name: "Keycap: 3", aliases: ["three"]),
    EmojiResult(emoji: "4️⃣", name: "Keycap: 4", aliases: ["four"]),
    EmojiResult(emoji: "5️⃣", name: "Keycap: 5", aliases: ["five"]),
    EmojiResult(emoji: "6️⃣", name: "Keycap: 6", aliases: ["six"]),
    EmojiResult(emoji: "7️⃣", name: "Keycap: 7", aliases: ["seven"]),
    EmojiResult(emoji: "8️⃣", name: "Keycap: 8", aliases: ["eight"]),
    EmojiResult(emoji: "9️⃣", name: "Keycap: 9", aliases: ["nine"]),
    EmojiResult(emoji: "🏳️‍🌈", name: "Rainbow flag", aliases: ["pride", "lgbtq"]),
    EmojiResult(emoji: "🏳️‍⚧️", name: "Transgender flag", aliases: ["trans", "pride"]),
    EmojiResult(emoji: "🏴‍☠️", name: "Pirate flag", aliases: ["jolly roger"]),
    EmojiResult(emoji: "👁️‍🗨️", name: "Eye in speech bubble", aliases: ["witness"]),
    EmojiResult(emoji: "❤️‍🔥", name: "Heart on fire", aliases: ["love", "passion"]),
    EmojiResult(emoji: "❤️‍🩹", name: "Mending heart", aliases: ["healing", "recovery"]),
    EmojiResult(emoji: "🐦‍🔥", name: "Phoenix", aliases: ["rebirth", "firebird"]),
    EmojiResult(emoji: "🍄‍🟫", name: "Brown mushroom", aliases: ["fungus"]),
    EmojiResult(emoji: "🍋‍🟩", name: "Lime", aliases: ["citrus", "green"]),
    EmojiResult(emoji: "⛓️‍💥", name: "Broken chain", aliases: ["freedom", "unlink"]),
    EmojiResult(emoji: "👨‍👩‍👧‍👦", name: "Family: man, woman, girl, boy", aliases: ["parents", "children"]),
    EmojiResult(emoji: "👩‍👩‍👧‍👧", name: "Family: woman, woman, girl, girl", aliases: ["mothers", "children"]),
    EmojiResult(emoji: "👨‍👨‍👦‍👦", name: "Family: man, man, boy, boy", aliases: ["fathers", "children"]),
    EmojiResult(emoji: "🧑‍🧑‍🧒‍🧒", name: "Family: adult, adult, child, child", aliases: ["parents", "children"]),
    EmojiResult(emoji: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", name: "Flag: England", aliases: ["english"]),
    EmojiResult(emoji: "🏴󠁧󠁢󠁳󠁣󠁴󠁿", name: "Flag: Scotland", aliases: ["scottish"]),
    EmojiResult(emoji: "🏴󠁧󠁢󠁷󠁬󠁳󠁿", name: "Flag: Wales", aliases: ["welsh"]),
  ]

  private static let professionEntries: [EmojiResult] = {
    let people = [
      (emoji: "🧑", name: "person"),
      (emoji: "👩", name: "woman"),
      (emoji: "👨", name: "man"),
    ]
    let roles: [(emoji: String, name: String, aliases: [String])] = [
      ("⚕️", "health worker", ["doctor", "nurse", "medic"]),
      ("🎓", "student", ["graduate"]),
      ("🏫", "teacher", ["professor", "educator"]),
      ("⚖️", "judge", ["justice"]),
      ("🌾", "farmer", ["agriculture"]),
      ("🍳", "cook", ["chef"]),
      ("🔧", "mechanic", ["repair"]),
      ("🏭", "factory worker", ["industrial"]),
      ("💼", "office worker", ["business"]),
      ("🔬", "scientist", ["researcher"]),
      ("💻", "technologist", ["developer", "programmer", "coder"]),
      ("🎤", "singer", ["musician"]),
      ("🎨", "artist", ["painter"]),
      ("✈️", "pilot", ["aviator"]),
      ("🚀", "astronaut", ["space"]),
      ("🚒", "firefighter", ["fireman"]),
    ]

    var results: [EmojiResult] = []
    for person in people {
      for role in roles {
        results.append(
          EmojiResult(
            emoji: person.emoji + "‍" + role.emoji,
            name: "\(sentenceCase(person.name)) \(role.name)",
            aliases: role.aliases
          ))
        for tone in skinTones {
          results.append(
            EmojiResult(
              emoji: person.emoji + tone.emoji + "‍" + role.emoji,
              name: "\(sentenceCase(person.name)) \(role.name): \(tone.name) skin tone",
              aliases: role.aliases + [tone.name]
            ))
        }
      }
    }
    return results
  }()

  private static let flagEntries: [EmojiResult] = {
    let english = Locale(identifier: "en_US_POSIX")
    var regions = Locale.Region.isoRegions.map(\.identifier).filter { code in
      code.count == 2 && code.unicodeScalars.allSatisfy {
        CharacterSet.uppercaseLetters.contains($0)
      }
    }
    regions += ["EU", "UN", "XK"]

    return Array(Set(regions)).sorted().compactMap { code in
      let scalars = code.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
        Unicode.Scalar(127_397 + scalar.value)
      }
      guard scalars.count == 2 else { return nil }

      let country = english.localizedString(forRegionCode: code) ?? code
      var aliases = [code.lowercased()]
      switch code {
      case "US": aliases += ["usa", "america", "american"]
      case "GB": aliases += ["uk", "britain", "british"]
      case "KR": aliases += ["south korea", "korean"]
      case "KP": aliases += ["north korea", "korean"]
      case "CZ": aliases += ["czech republic"]
      default: break
      }
      return EmojiResult(
        emoji: String(String.UnicodeScalarView(scalars)),
        name: "Flag: \(country)",
        aliases: aliases
      )
    }
  }()

  private static let querySynonyms: [String: [String]] = [
    "kitty": ["cat"],
    "kitten": ["cat"],
    "puppy": ["dog"],
    "poop": ["poo"],
    "shit": ["poo"],
    "smiley": ["smile", "smiling"],
    "happy": ["smile", "smiling"],
    "sad": ["cry", "crying", "frown"],
  ]

  private static func score(_ entry: CatalogEntry, for query: String) -> Int? {
    let queryWords = query.split(separator: " ").map(String.init)
    var total = 0

    for queryWord in queryWords {
      let alternatives = [queryWord] + (querySynonyms[queryWord] ?? [])
      let best = alternatives.flatMap { alternative in
        entry.words.map { wordScore(alternative, candidate: $0) }
      }.max() ?? 0
      guard best > 0 else { return nil }
      total += best
    }

    if entry.normalizedFields.contains(query) {
      total += 5_000
    } else if entry.normalizedFields.contains(where: { $0.hasPrefix(query) }) {
      total += 3_500
    } else if entry.normalizedFields.contains(where: { $0.contains(query) }) {
      total += 2_500
    }
    return total - entry.result.name.count
  }

  private static func wordScore(_ query: String, candidate: String) -> Int {
    if query == candidate { return 1_000 }
    if candidate.hasPrefix(query) { return 900 - (candidate.count - query.count) }
    if candidate.contains(query) { return 800 - (candidate.count - query.count) }
    if let gap = subsequenceGap(query, in: candidate) {
      return max(1, 650 - gap * 8)
    }

    let allowedDistance = query.count >= 7 ? 2 : 1
    guard abs(query.count - candidate.count) <= allowedDistance else { return 0 }
    let distance = editDistance(query, candidate)
    guard distance <= allowedDistance else { return 0 }
    return 500 - distance * 40
  }

  private static func subsequenceGap(_ query: String, in candidate: String) -> Int? {
    var remaining = query[...]
    var firstMatch: Int?
    var lastMatch = 0
    var index = 0

    for character in candidate {
      if character == remaining.first {
        firstMatch = firstMatch ?? index
        lastMatch = index
        remaining.removeFirst()
        if remaining.isEmpty { break }
      }
      index += 1
    }
    guard remaining.isEmpty, let firstMatch else { return nil }
    return firstMatch * 3 + (lastMatch - firstMatch + 1 - query.count)
  }

  private static func editDistance(_ left: String, _ right: String) -> Int {
    let left = Array(left)
    let right = Array(right)
    var previous = Array(0...right.count)

    for (leftIndex, leftCharacter) in left.enumerated() {
      var current = [leftIndex + 1]
      for (rightIndex, rightCharacter) in right.enumerated() {
        current.append(
          min(
            current[rightIndex] + 1,
            previous[rightIndex + 1] + 1,
            previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
          ))
      }
      previous = current
    }
    return previous[right.count]
  }

  private static func normalize(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    let searchable = folded.unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
    }
    return String(searchable).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  private static func sentenceCase(_ value: String) -> String {
    let lowercased = value.replacingOccurrences(of: "-", with: " ").lowercased()
    guard let first = lowercased.first else { return value }
    return first.uppercased() + lowercased.dropFirst()
  }
}
