import Foundation

struct AHDEntry: Equatable {
  let headword: String
  let partOfSpeech: String
  let definition: String
}

struct AHDLookupResult: Equatable {
  let entry: AHDEntry?
  let suggestions: [String]
}

enum AHDResponseParser {
  static func suggestions(from data: Data) -> [String] {
    let delegate = AHDSuggestionParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    return delegate.terms
  }

  static func entry(from data: Data) -> AHDEntry? {
    let delegate = AHDDefinitionParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    return delegate.entry
  }
}

private final class AHDSuggestionParser: NSObject, XMLParserDelegate {
  private var term = ""
  private var isReadingTerm = false
  fileprivate var terms: [String] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard elementName == "term" else { return }
    term = ""
    isReadingTerm = true
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if isReadingTerm { term += string }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    guard elementName == "term", isReadingTerm else { return }
    let normalized = normalizeAHDText(term)
    if !normalized.isEmpty, !terms.contains(normalized) { terms.append(normalized) }
    isReadingTerm = false
  }
}
