import Foundation

enum RainForecast {
  private struct Payload: Decodable {
    let timezone: String?
    let utcOffsetSeconds: Int?
    let current: Current?
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
      case timezone
      case utcOffsetSeconds = "utc_offset_seconds"
      case current
      case hourly
    }
  }

  private struct Current: Decodable {
    let time: String
  }

  private struct Hourly: Decodable {
    let time: [String]
    let precipitationProbability: [Double?]?
    let rain: [Double?]?
    let showers: [Double?]?
    let weatherCode: [Int?]?

    enum CodingKeys: String, CodingKey {
      case time
      case precipitationProbability = "precipitation_probability"
      case rain
      case showers
      case weatherCode = "weather_code"
    }
  }

  private struct Hour {
    let timestamp: String
    let probability: Double?
    let amount: Double
    let weatherCode: Int?

    var day: String { String(timestamp.prefix(10)) }
  }

  private static let rainyWeatherCodes = Set(
    [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]
  )
  private static let drizzleWeatherCodes = Set([51, 53, 55, 56, 57, 80])
  private static let pouringWeatherCodes = Set([65, 67, 82, 95, 96, 99])

  static func summary(
    from data: Data,
    now: Date = Date(),
    locale: Locale = .current
  ) -> String? {
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
      !payload.hourly.time.isEmpty
    else { return nil }

    let currentTimestamp =
      payload.current?.time
      ?? timestamp(
        for: now,
        timezone: payload.timezone,
        utcOffsetSeconds: payload.utcOffsetSeconds
      )
    let today = String(currentTimestamp.prefix(10))
    let currentHour = String(currentTimestamp.prefix(13)) + ":00"
    guard today.count == 10, currentHour.count == 16 else { return nil }

    let hours = payload.hourly.time.indices.map { index in
      Hour(
        timestamp: payload.hourly.time[index],
        probability: value(at: index, in: payload.hourly.precipitationProbability),
        amount: (value(at: index, in: payload.hourly.rain) ?? 0)
          + (value(at: index, in: payload.hourly.showers) ?? 0),
        weatherCode: value(at: index, in: payload.hourly.weatherCode)
      )
    }

    if let startIndex = hours.firstIndex(where: {
      $0.day == today && $0.timestamp >= currentHour && isRainy($0)
    }) {
      var endIndex = startIndex
      while endIndex + 1 < hours.count,
        hours[endIndex + 1].day == today,
        isRainy(hours[endIndex + 1])
      {
        endIndex += 1
      }

      let period = Array(hours[startIndex...endIndex])
      let start =
        hours[startIndex].timestamp == currentHour
        ? "Now"
        : formattedHour(from: hours[startIndex].timestamp)
      guard let start else { return nil }
      return "\(start) (\(description(for: period)))"
    }

    guard let nextRain = hours.first(where: { $0.day > today && isRainy($0) }) else {
      return "No rain forecast"
    }
    return weekdayName(
      for: nextRain.day,
      timezone: payload.timezone,
      utcOffsetSeconds: payload.utcOffsetSeconds,
      locale: locale
    ) ?? nextRain.day
  }

  private static func isRainy(_ hour: Hour) -> Bool {
    let hasRainSignal =
      hour.amount >= 0.1
      || hour.weatherCode.map(rainyWeatherCodes.contains) == true
    guard hasRainSignal else { return false }
    guard let probability = hour.probability else { return true }
    return probability >= 30 || hour.amount >= 1
      || hour.weatherCode.map(pouringWeatherCodes.contains) == true
  }

  private static func description(for hours: [Hour]) -> String {
    let maximumAmount = hours.map(\.amount).max() ?? 0
    let codes = hours.compactMap(\.weatherCode)
    if maximumAmount >= 4 || codes.contains(where: pouringWeatherCodes.contains) {
      return "pouring"
    }
    if maximumAmount <= 0.5 || (!codes.isEmpty && codes.allSatisfy(drizzleWeatherCodes.contains)) {
      return "drizzle"
    }
    return hours.count == 1 ? "1 hour" : "\(hours.count) hours"
  }

  private static func formattedHour(from timestamp: String) -> String? {
    guard timestamp.count >= 13,
      let hour = Int(timestamp.dropFirst(11).prefix(2)),
      (0...23).contains(hour)
    else { return nil }
    let suffix = hour < 12 ? "AM" : "PM"
    let displayHour = hour % 12 == 0 ? 12 : hour % 12
    return "\(displayHour)\(suffix)"
  }

  private static func weekdayName(
    for day: String,
    timezone: String?,
    utcOffsetSeconds: Int?,
    locale: Locale
  ) -> String? {
    let pieces = day.split(separator: "-").compactMap { Int($0) }
    guard pieces.count == 3 else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone(identifier: timezone, offsetSeconds: utcOffsetSeconds)
    guard
      let date = calendar.date(
        from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    else { return nil }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateFormat = "EEEE"
    return formatter.string(from: date)
  }

  private static func timestamp(
    for date: Date,
    timezone: String?,
    utcOffsetSeconds: Int?
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone(identifier: timezone, offsetSeconds: utcOffsetSeconds)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.string(from: date)
  }

  private static func timeZone(identifier: String?, offsetSeconds: Int?) -> TimeZone {
    identifier.flatMap(TimeZone.init(identifier:))
      ?? offsetSeconds.flatMap(TimeZone.init(secondsFromGMT:))
      ?? .current
  }

  private static func value<T>(at index: Int, in values: [T?]?) -> T? {
    guard let values, values.indices.contains(index) else { return nil }
    return values[index]
  }
}
