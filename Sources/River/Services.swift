import AppKit
import CoreServices
import Foundation

struct FileResult: Equatable {
  let path: String

  var title: String { URL(fileURLWithPath: path).lastPathComponent }

  var subtitle: String {
    let home = Paths.homeDirectory
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
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
}
