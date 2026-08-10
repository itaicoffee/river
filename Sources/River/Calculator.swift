import Foundation

struct CalculationResult: Equatable {
  let display: String
  let copyText: String
}

enum Calculator {
  private enum Dimension {
    case length
    case mass
    case time
    case data
    case temperature
  }

  private struct UnitDefinition {
    let dimension: Dimension
    let symbol: String
    let scale: Double
    let offset: Double

    func valueInBaseUnit(_ value: Double) -> Double {
      (value + offset) * scale
    }

    func valueFromBaseUnit(_ value: Double) -> Double {
      value / scale - offset
    }
  }

  static func calculate(_ input: String) -> CalculationResult? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if let conversion = conversionParts(in: text),
      let source = units[conversion.source.lowercased()],
      let target = units[conversion.target.lowercased()],
      source.dimension == target.dimension,
      let value = expressionValue(conversion.expression)
    {
      let converted = target.valueFromBaseUnit(source.valueInBaseUnit(value))
      guard converted.isFinite else { return nil }
      let output = "\(format(converted)) \(target.symbol)"
      return CalculationResult(display: output, copyText: output)
    }

    guard let value = expressionValue(text), value.isFinite else { return nil }
    let output = format(value)
    return CalculationResult(display: output, copyText: output)
  }

  private static func conversionParts(in input: String) -> (
    expression: String, source: String, target: String
  )? {
    let pattern = #"^(.+?)\s+([A-Za-z°]+)\s+(?:in|to)\s+([A-Za-z°]+)$"#
    guard
      let expression = try? NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive])
    else { return nil }

    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    guard let match = expression.firstMatch(in: input, range: range), match.range == range,
      let valueRange = Range(match.range(at: 1), in: input),
      let sourceRange = Range(match.range(at: 2), in: input),
      let targetRange = Range(match.range(at: 3), in: input)
    else { return nil }

    return (
      String(input[valueRange]),
      String(input[sourceRange]),
      String(input[targetRange])
    )
  }

  private static func expressionValue(_ expression: String) -> Double? {
    var parser = ExpressionParser(expression)
    return parser.parse()
  }

  private static func format(_ value: Double) -> String {
    let normalized = abs(value) < 0.000_000_000_001 ? 0 : value
    if abs(normalized) >= 1_000_000_000_000
      || (normalized != 0 && abs(normalized) < 0.000_000_001)
    {
      return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), normalized)
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 10
    return formatter.string(from: NSNumber(value: normalized)) ?? String(normalized)
  }

  private static let units: [String: UnitDefinition] = {
    var definitions: [String: UnitDefinition] = [:]

    func add(
      _ aliases: [String], dimension: Dimension, symbol: String, scale: Double,
      offset: Double = 0
    ) {
      let unit = UnitDefinition(
        dimension: dimension, symbol: symbol, scale: scale, offset: offset)
      for alias in aliases { definitions[alias] = unit }
    }

    add(["mm", "millimeter", "millimeters"], dimension: .length, symbol: "mm", scale: 0.001)
    add(["cm", "centimeter", "centimeters"], dimension: .length, symbol: "cm", scale: 0.01)
    add(["m", "meter", "meters"], dimension: .length, symbol: "m", scale: 1)
    add(["km", "kilometer", "kilometers"], dimension: .length, symbol: "km", scale: 1_000)
    add(["in", "inch", "inches"], dimension: .length, symbol: "in", scale: 0.0254)
    add(["ft", "foot", "feet"], dimension: .length, symbol: "ft", scale: 0.3048)
    add(["yd", "yard", "yards"], dimension: .length, symbol: "yd", scale: 0.9144)
    add(["mi", "mile", "miles"], dimension: .length, symbol: "mi", scale: 1_609.344)

    add(["mg", "milligram", "milligrams"], dimension: .mass, symbol: "mg", scale: 0.000_001)
    add(["g", "gram", "grams"], dimension: .mass, symbol: "g", scale: 0.001)
    add(["kg", "kilogram", "kilograms"], dimension: .mass, symbol: "kg", scale: 1)
    add(["oz", "ounce", "ounces"], dimension: .mass, symbol: "oz", scale: 0.028_349_523_125)
    add(["lb", "lbs", "pound", "pounds"], dimension: .mass, symbol: "lb", scale: 0.453_592_37)

    add(["ms", "millisecond", "milliseconds"], dimension: .time, symbol: "ms", scale: 0.001)
    add(["s", "sec", "second", "seconds"], dimension: .time, symbol: "s", scale: 1)
    add(["min", "minute", "minutes"], dimension: .time, symbol: "min", scale: 60)
    add(["h", "hr", "hour", "hours"], dimension: .time, symbol: "h", scale: 3_600)
    add(["day", "days"], dimension: .time, symbol: "days", scale: 86_400)

    add(["b", "byte", "bytes"], dimension: .data, symbol: "B", scale: 1)
    add(["kb"], dimension: .data, symbol: "KB", scale: 1_000)
    add(["mb"], dimension: .data, symbol: "MB", scale: 1_000_000)
    add(["gb"], dimension: .data, symbol: "GB", scale: 1_000_000_000)
    add(["tb"], dimension: .data, symbol: "TB", scale: 1_000_000_000_000)
    add(["kib"], dimension: .data, symbol: "KiB", scale: 1_024)
    add(["mib"], dimension: .data, symbol: "MiB", scale: 1_048_576)
    add(["gib"], dimension: .data, symbol: "GiB", scale: 1_073_741_824)

    add(["c", "°c", "celsius"], dimension: .temperature, symbol: "°C", scale: 1, offset: 273.15)
    add(
      ["f", "°f", "fahrenheit"], dimension: .temperature, symbol: "°F", scale: 5 / 9,
      offset: 459.67)
    add(["k", "kelvin"], dimension: .temperature, symbol: "K", scale: 1)

    return definitions
  }()
}

private struct ExpressionParser {
  private let characters: [Character]
  private var index = 0

  init(_ expression: String) {
    characters = Array(
      expression
        .replacingOccurrences(of: "×", with: "*")
        .replacingOccurrences(of: "÷", with: "/")
        .replacingOccurrences(of: "−", with: "-"))
  }

  mutating func parse() -> Double? {
    guard let value = parseExpression() else { return nil }
    skipWhitespace()
    return index == characters.count ? value : nil
  }

  private mutating func parseExpression() -> Double? {
    guard var value = parseTerm() else { return nil }
    while true {
      if consume("+") {
        guard let right = parseTerm() else { return nil }
        value += right
      } else if consume("-") {
        guard let right = parseTerm() else { return nil }
        value -= right
      } else {
        return value
      }
    }
  }

  private mutating func parseTerm() -> Double? {
    guard var value = parseUnary() else { return nil }
    while true {
      if consume("*") || consumeWord("of") {
        guard let right = parseUnary() else { return nil }
        value *= right
      } else if consume("/") {
        guard let right = parseUnary(), right != 0 else { return nil }
        value /= right
      } else {
        return value
      }
    }
  }

  private mutating func parsePower() -> Double? {
    guard var value = parsePostfix() else { return nil }
    if consume("^") {
      guard let exponent = parseUnary() else { return nil }
      value = Foundation.pow(value, exponent)
    }
    return value
  }

  private mutating func parseUnary() -> Double? {
    if consume("+") { return parseUnary() }
    if consume("-") { return parseUnary().map { -$0 } }
    return parsePower()
  }

  private mutating func parsePostfix() -> Double? {
    guard var value = parsePrimary() else { return nil }
    while consume("%") { value /= 100 }
    return value
  }

  private mutating func parsePrimary() -> Double? {
    skipWhitespace()
    if consume("(") {
      guard let value = parseExpression(), consume(")") else { return nil }
      return value
    }

    if let number = parseNumber() { return number }
    guard let identifier = parseIdentifier() else { return nil }
    switch identifier {
    case "pi", "π": return Double.pi
    case "e": return Foundation.exp(1)
    case "sqrt": return parseFunction(Foundation.sqrt)
    case "abs": return parseFunction(Swift.abs)
    case "sin": return parseFunction(Foundation.sin)
    case "cos": return parseFunction(Foundation.cos)
    case "tan": return parseFunction(Foundation.tan)
    case "ln": return parseFunction(Foundation.log)
    case "log": return parseFunction(Foundation.log10)
    default: return nil
    }
  }

  private mutating func parseFunction(_ function: (Double) -> Double) -> Double? {
    let value: Double?
    if consume("(") {
      value = parseExpression()
      guard consume(")") else { return nil }
    } else {
      value = parseUnary()
    }
    guard let value else { return nil }
    let result = function(value)
    return result.isFinite ? result : nil
  }

  private mutating func parseNumber() -> Double? {
    skipWhitespace()
    let start = index
    var sawDigit = false
    while index < characters.count, characters[index].isNumber || characters[index] == "." {
      sawDigit = sawDigit || characters[index].isNumber
      index += 1
    }
    guard sawDigit else {
      index = start
      return nil
    }

    if index < characters.count, characters[index] == "e" || characters[index] == "E" {
      let exponentStart = index
      index += 1
      if index < characters.count, characters[index] == "+" || characters[index] == "-" {
        index += 1
      }
      let digitsStart = index
      while index < characters.count, characters[index].isNumber { index += 1 }
      if digitsStart == index { index = exponentStart }
    }

    return Double(String(characters[start..<index]))
  }

  private mutating func parseIdentifier() -> String? {
    skipWhitespace()
    let start = index
    while index < characters.count,
      characters[index].isLetter || characters[index] == "π"
    {
      index += 1
    }
    guard start != index else { return nil }
    return String(characters[start..<index]).lowercased()
  }

  private mutating func consume(_ character: Character) -> Bool {
    skipWhitespace()
    guard index < characters.count, characters[index] == character else { return false }
    index += 1
    return true
  }

  private mutating func consumeWord(_ word: String) -> Bool {
    skipWhitespace()
    let start = index
    for character in word {
      guard index < characters.count,
        String(characters[index]).lowercased() == String(character)
      else {
        index = start
        return false
      }
      index += 1
    }
    if index < characters.count, characters[index].isLetter {
      index = start
      return false
    }
    return true
  }

  private mutating func skipWhitespace() {
    while index < characters.count, characters[index].isWhitespace { index += 1 }
  }
}
