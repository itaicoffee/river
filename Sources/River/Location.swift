import CoreLocation
import Foundation

struct RiverLocation: Codable, Equatable {
  let latitude: Double
  let longitude: Double
  let updatedAt: Date

  var pluginEnvironment: [String: String] {
    let locale = Locale(identifier: "en_US_POSIX")
    return [
      "RIVER_LATITUDE": String(format: "%.6f", locale: locale, latitude),
      "RIVER_LONGITUDE": String(format: "%.6f", locale: locale, longitude),
    ]
  }

  func isNear(_ other: RiverLocation) -> Bool {
    abs(latitude - other.latitude) < 0.001 && abs(longitude - other.longitude) < 0.001
  }
}

final class RiverLocationProvider: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let cachePath: String
  private var requestOutstanding = false
  private(set) var currentLocation: RiverLocation?
  var onChange: ((RiverLocation) -> Void)?

  init(cachePath: String = Paths.locationCacheFile) {
    self.cachePath = cachePath
    currentLocation = Self.loadCache(at: cachePath)
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func refresh() {
    guard CLLocationManager.locationServicesEnabled() else { return }
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways:
      requestCurrentLocation()
    #if !os(macOS)
    case .authorizedWhenInUse:
      requestCurrentLocation()
    #endif
    case .denied, .restricted:
      return
    @unknown default:
      return
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways {
      requestCurrentLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    requestOutstanding = false
    guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }) else { return }
    let updated = RiverLocation(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      updatedAt: location.timestamp
    )
    let changed = currentLocation.map { !$0.isNear(updated) } ?? true
    currentLocation = updated
    persist(updated)
    if changed { onChange?(updated) }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    requestOutstanding = false
    let coreLocationError = error as? CLError
    if coreLocationError?.code != .locationUnknown {
      fputs("river: could not update location: \(error.localizedDescription)\n", stderr)
    }
  }

  private func requestCurrentLocation() {
    guard !requestOutstanding else { return }
    requestOutstanding = true
    manager.requestLocation()
  }

  private static func loadCache(at path: String) -> RiverLocation? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(RiverLocation.self, from: data)
  }

  private func persist(_ location: RiverLocation) {
    let url = URL(fileURLWithPath: cachePath)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(location).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      fputs("river: could not cache location: \(error.localizedDescription)\n", stderr)
    }
  }
}
