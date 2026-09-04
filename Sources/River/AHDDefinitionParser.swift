import Foundation

final class AHDDefinitionParser: NSObject, XMLParserDelegate {
  private var depth = 0
  private var resultsDepth: Int?
  private var headwordDepth: Int?
  private var partOfSpeechDepth: Int?
  private var definitionDepth: Int?
  private var firstPartOfSpeechSegmentDepth: Int?
  private var headwordText = ""
  private var partOfSpeechText = ""
  private var definitionText = ""
  private var partOfSpeechSegmentText = ""
  private var headword: String?
  private var partOfSpeech: String?
  private var definition: String?

  var entry: AHDEntry? {
    guard let headword, let definition, !headword.isEmpty, !definition.isEmpty else { return nil }
    return AHDEntry(
      headword: headword,
      partOfSpeech: partOfSpeech ?? "",
      definition: definition
    )
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    depth += 1

    if resultsDepth == nil, attributeDict["id"] == "results" {
      resultsDepth = depth
    }
    guard resultsDepth != nil else { return }

    let classes = Set((attributeDict["class"] ?? "").split(separator: " ").map(String.init))
    if headword == nil, headwordDepth == nil, elementName == "font",
      attributeDict["color"]?.lowercased() == "#006595"
    {
      headwordText = ""
      headwordDepth = depth
    }

    if definition == nil, firstPartOfSpeechSegmentDepth == nil, classes.contains("pseg") {
      partOfSpeechSegmentText = ""
      firstPartOfSpeechSegmentDepth = depth
    }

    if firstPartOfSpeechSegmentDepth != nil, partOfSpeech == nil,
      partOfSpeechDepth == nil, definitionDepth == nil, elementName == "i"
    {
      partOfSpeechText = ""
      partOfSpeechDepth = depth
    }

    if definition == nil, definitionDepth == nil, classes.contains("ds-list") {
      definitionText = ""
      definitionDepth = depth
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if headwordDepth != nil { headwordText += string }
    if partOfSpeechDepth != nil { partOfSpeechText += string }
    if definitionDepth != nil { definitionText += string }
    if firstPartOfSpeechSegmentDepth != nil { partOfSpeechSegmentText += string }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if depth == headwordDepth {
      let normalized = normalizeAHDText(headwordText)
      if !normalized.isEmpty { headword = normalized }
      headwordDepth = nil
    }

    if depth == partOfSpeechDepth {
      let normalized = normalizeAHDText(partOfSpeechText)
      if !normalized.isEmpty { partOfSpeech = normalized }
      partOfSpeechDepth = nil
    }

    if depth == definitionDepth {
      let normalized = stripAHDSenseNumber(from: normalizeAHDText(definitionText))
      if !normalized.isEmpty { definition = normalized }
      definitionDepth = nil
    }

    if depth == firstPartOfSpeechSegmentDepth {
      if definition == nil {
        var fallback = normalizeAHDText(partOfSpeechSegmentText)
        if let partOfSpeech, fallback.hasPrefix(partOfSpeech) {
          fallback.removeFirst(partOfSpeech.count)
        }
        fallback = stripAHDSenseNumber(from: normalizeAHDText(fallback))
        if !fallback.isEmpty { definition = fallback }
      }
      firstPartOfSpeechSegmentDepth = nil
    }

    if depth == resultsDepth { resultsDepth = nil }
    depth -= 1
  }
}

func normalizeAHDText(_ text: String) -> String {
  text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func stripAHDSenseNumber(from text: String) -> String {
  text.replacingOccurrences(
    of: #"^\d+\.\s*"#,
    with: "",
    options: .regularExpression
  )
}
