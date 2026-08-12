import Darwin
import Foundation

struct StatusPluginDescriptor: Equatable {
  static let minimumInterval: TimeInterval = 5
  static let maximumInterval: TimeInterval = 7 * 24 * 60 * 60

  let filename: String
  let displayName: String
  let path: String
  let interval: TimeInterval
  let modificationDate: Date?
  let fileSize: UInt64?

  init?(
    filename: String,
    directory: String,
    modificationDate: Date? = nil,
    fileSize: UInt64? = nil
  ) {
    let pieces = filename.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard pieces.count >= 2 else { return nil }

    let candidateIndexes = [pieces.count - 1, pieces.count - 2].filter { $0 > 0 }
    guard let intervalIndex = candidateIndexes.first(where: {
      Self.interval(from: pieces[$0]) != nil
    }), let interval = Self.interval(from: pieces[intervalIndex])
    else {
      return nil
    }

    // The refresh token may be the final component or immediately precede one
    // conventional script extension, matching xbar's filename convention.
    guard intervalIndex == pieces.count - 1 || intervalIndex == pieces.count - 2 else {
      return nil
    }
    let name = pieces[..<intervalIndex].joined(separator: ".")
    guard !name.isEmpty else { return nil }

    let cleanedName = name.replacingOccurrences(
      of: "^[0-9]+[-_ ]*", with: "", options: .regularExpression)
    self.filename = filename
    self.displayName = cleanedName.isEmpty ? name : cleanedName
    self.path = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
    self.interval = interval
    self.modificationDate = modificationDate
    self.fileSize = fileSize
  }

  private static func interval(from token: String) -> TimeInterval? {
    guard let unit = token.last, "smhd".contains(unit) else { return nil }
    let number = token.dropLast()
    guard !number.isEmpty, number.allSatisfy(\.isNumber), let count = TimeInterval(number), count > 0
    else {
      return nil
    }

    let multiplier: TimeInterval
    switch unit {
    case "s": multiplier = 1
    case "m": multiplier = 60
    case "h": multiplier = 60 * 60
    case "d": multiplier = 24 * 60 * 60
    default: return nil
    }
    let interval = count * multiplier
    guard (minimumInterval...maximumInterval).contains(interval) else { return nil }
    return interval
  }
}

struct StatusPluginSnapshot: Equatable {
  let id: String
  let displayName: String
  let output: String?

  var displayText: String { output ?? "\(displayName) …" }
}

enum StatusPluginOutput {
  static let maximumBytes = 16 * 1024

  static func firstLine(from data: Data) -> String? {
    String(decoding: data.prefix(maximumBytes), as: UTF8.self)
      .split(whereSeparator: { $0.isNewline })
      .lazy
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
  }
}

struct StatusPluginExecutionResult: Equatable {
  let output: String?
  let error: String?
}

enum StatusPluginProcessRunner {
  static func run(
    _ descriptor: StatusPluginDescriptor,
    timeoutMilliseconds: Int
  ) -> StatusPluginExecutionResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: descriptor.path)
    process.currentDirectoryURL = URL(fileURLWithPath: descriptor.path).deletingLastPathComponent()
    process.standardOutput = stdout
    process.standardError = stderr

    let outputCollector = BoundedPipeCollector(stdout, limit: StatusPluginOutput.maximumBytes)
    let errorCollector = BoundedPipeCollector(stderr, limit: StatusPluginOutput.maximumBytes)
    do {
      try process.run()
    } catch {
      return StatusPluginExecutionResult(output: nil, error: error.localizedDescription)
    }

    let deadline = DispatchTime.now() + .milliseconds(timeoutMilliseconds)
    let timedOut = wait(for: process, until: deadline) == false
    if timedOut { terminateAndWait(process) }

    let outputData = outputCollector.readToEnd()
    let errorData = errorCollector.readToEnd()
    if timedOut {
      return StatusPluginExecutionResult(output: nil, error: "timed out")
    }
    guard process.terminationStatus == 0 else {
      let message = StatusPluginOutput.firstLine(from: errorData)
        ?? "exited with status \(process.terminationStatus)"
      return StatusPluginExecutionResult(output: nil, error: message)
    }
    guard let output = StatusPluginOutput.firstLine(from: outputData) else {
      return StatusPluginExecutionResult(output: nil, error: "produced no output")
    }
    return StatusPluginExecutionResult(output: output, error: nil)
  }

  private static func wait(for process: Process, until deadline: DispatchTime) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in semaphore.signal() }
    if !process.isRunning { return true }
    return semaphore.wait(timeout: deadline) == .success
  }

  private static func terminateAndWait(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    if wait(for: process, until: .now() + .milliseconds(250)) == false {
      Darwin.kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
    }
  }
}

private final class BoundedPipeCollector {
  private let group = DispatchGroup()
  private let lock = NSLock()
  private let limit: Int
  private var data = Data()
  private var finished = false

  init(_ pipe: Pipe, limit: Int) {
    self.limit = limit
    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else {
        handle.readabilityHandler = nil
        return
      }

      let chunk = handle.availableData
      guard chunk.isEmpty else {
        self.lock.lock()
        let remaining = max(0, self.limit - self.data.count)
        if remaining > 0 { self.data.append(chunk.prefix(remaining)) }
        self.lock.unlock()
        return
      }

      handle.readabilityHandler = nil
      self.lock.lock()
      let shouldLeave = !self.finished
      self.finished = true
      self.lock.unlock()
      if shouldLeave { self.group.leave() }
    }
  }

  func readToEnd() -> Data {
    group.wait()
    lock.lock()
    defer { lock.unlock() }
    return data
  }
}

final class StatusPluginManager {
  private struct CacheEntry: Codable, Equatable {
    let output: String
    let updatedAt: Date
  }

  private final class Runtime {
    let descriptor: StatusPluginDescriptor
    let token = UUID()
    var nextRun: Date
    var isRunning = false

    init(descriptor: StatusPluginDescriptor, nextRun: Date) {
      self.descriptor = descriptor
      self.nextRun = nextRun
    }
  }

  private let queue = DispatchQueue(label: "river.status-plugins", qos: .utility)
  private let workerQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "river.status-plugin-workers"
    queue.qualityOfService = .utility
    queue.maxConcurrentOperationCount = 2
    return queue
  }()
  private let snapshotLock = NSLock()
  private let cachePath: String
  private var timer: DispatchSourceTimer?
  private var config = AppConfig()
  private var runtimes: [String: Runtime] = [:]
  private var cache: [String: CacheEntry] = [:]
  private var publishedSnapshots: [StatusPluginSnapshot] = []
  private var lastScan = Date.distantPast

  var onChange: (([StatusPluginSnapshot]) -> Void)?

  init(cachePath: String = Paths.statusPluginCacheFile) {
    self.cachePath = cachePath
  }

  var snapshots: [StatusPluginSnapshot] {
    snapshotLock.lock()
    defer { snapshotLock.unlock() }
    return publishedSnapshots
  }

  func start(config: AppConfig) {
    queue.sync {
      guard timer == nil else { return }
      self.config = config
      cache = Self.loadCache(at: cachePath)
      reconcilePlugins(now: Date())
      publishIfNeeded()

      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
      timer.setEventHandler { [weak self] in self?.tick() }
      self.timer = timer
      timer.resume()
    }
  }

  func update(config: AppConfig) {
    queue.async { [weak self] in
      guard let self else { return }
      let directoryChanged = self.config.pluginDirectory != config.pluginDirectory
      self.config = config
      if directoryChanged {
        self.runtimes = [:]
        self.lastScan = .distantPast
      }
      self.reconcilePlugins(now: Date())
      self.publishIfNeeded()
    }
  }

  func stop() {
    queue.sync {
      timer?.cancel()
      timer = nil
      runtimes = [:]
    }
    workerQueue.cancelAllOperations()
  }

  private func tick() {
    let now = Date()
    if now.timeIntervalSince(lastScan) >= 2 {
      reconcilePlugins(now: now)
    }
    runDuePlugins(now: now)
  }

  private func reconcilePlugins(now: Date) {
    lastScan = now
    let directory = Paths.expand(config.pluginDirectory)
    let descriptors = Self.discover(in: directory)
    var updated: [String: Runtime] = [:]

    for descriptor in descriptors {
      if let existing = runtimes[descriptor.path], existing.descriptor == descriptor {
        updated[descriptor.path] = existing
      } else {
        updated[descriptor.path] = Runtime(descriptor: descriptor, nextRun: now)
      }
    }
    runtimes = updated

    let activePaths = Set(descriptors.map(\.path))
    let filteredCache = cache.filter { activePaths.contains($0.key) }
    if filteredCache != cache {
      cache = filteredCache
      persistCache()
    }
    publishIfNeeded()
  }

  private func runDuePlugins(now: Date) {
    let runningCount = runtimes.values.filter(\.isRunning).count
    var availableSlots = max(0, workerQueue.maxConcurrentOperationCount - runningCount)
    guard availableSlots > 0 else { return }

    let due = runtimes.values.filter { !$0.isRunning && $0.nextRun <= now }.sorted {
      if $0.nextRun != $1.nextRun { return $0.nextRun < $1.nextRun }
      return $0.descriptor.filename.localizedStandardCompare($1.descriptor.filename)
        == .orderedAscending
    }

    for runtime in due where availableSlots > 0 {
      availableSlots -= 1
      runtime.isRunning = true
      let descriptor = runtime.descriptor
      let token = runtime.token
      let timeout = config.pluginTimeoutMilliseconds
      workerQueue.addOperation { [weak self] in
        let result = StatusPluginProcessRunner.run(
          descriptor, timeoutMilliseconds: timeout)
        self?.queue.async { [weak self] in
          self?.complete(path: descriptor.path, token: token, result: result)
        }
      }
    }
  }

  private func complete(
    path: String,
    token: UUID,
    result: StatusPluginExecutionResult
  ) {
    guard let runtime = runtimes[path], runtime.token == token else { return }
    runtime.isRunning = false
    runtime.nextRun = Date().addingTimeInterval(runtime.descriptor.interval)

    if let output = result.output {
      cache[path] = CacheEntry(output: output, updatedAt: Date())
      persistCache()
      publishIfNeeded()
    } else if let error = result.error {
      fputs("river: status plugin '\(runtime.descriptor.filename)' \(error)\n", stderr)
    }
  }

  private func publishIfNeeded() {
    let values = runtimes.values.sorted {
      $0.descriptor.filename.localizedStandardCompare($1.descriptor.filename) == .orderedAscending
    }.map { runtime in
      StatusPluginSnapshot(
        id: runtime.descriptor.path,
        displayName: runtime.descriptor.displayName,
        output: cache[runtime.descriptor.path]?.output
      )
    }
    guard values != snapshots else { return }

    snapshotLock.lock()
    publishedSnapshots = values
    snapshotLock.unlock()
    DispatchQueue.main.async { [weak self] in
      self?.onChange?(values)
    }
  }

  private static func discover(in directory: String) -> [StatusPluginDescriptor] {
    let fileManager = FileManager.default
    let filenames = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
    return filenames.compactMap { filename in
      guard !filename.hasPrefix(".") else { return nil }
      let path = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
      guard fileManager.isExecutableFile(atPath: path) else { return nil }
      let attributes = try? fileManager.attributesOfItem(atPath: path)
      return StatusPluginDescriptor(
        filename: filename,
        directory: directory,
        modificationDate: attributes?[.modificationDate] as? Date,
        fileSize: (attributes?[.size] as? NSNumber)?.uint64Value
      )
    }
  }

  private static func loadCache(at path: String) -> [String: CacheEntry] {
    guard let data = FileManager.default.contents(atPath: path) else { return [:] }
    return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
  }

  private func persistCache() {
    let url = URL(fileURLWithPath: cachePath)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(cache)
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      fputs("river: could not write status plugin cache: \(error.localizedDescription)\n", stderr)
    }
  }

  deinit {
    timer?.cancel()
    workerQueue.cancelAllOperations()
  }
}
