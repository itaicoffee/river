import Foundation

private final class AHDResponseParts {
  private let lock = NSLock()
  private var definitionData: Data?
  private var suggestionData: Data?

  func setDefinitionData(_ data: Data?) {
    lock.lock()
    definitionData = data
    lock.unlock()
  }

  func setSuggestionData(_ data: Data?) {
    lock.lock()
    suggestionData = data
    lock.unlock()
  }

  func snapshot() -> (definition: Data?, suggestions: Data?) {
    lock.lock()
    defer { lock.unlock() }
    return (definitionData, suggestionData)
  }
}

final class AHDLookup {
  private let session: URLSession
  private var generation = 0
  private var pendingWorkItem: DispatchWorkItem?
  private var activeTasks: [URLSessionDataTask] = []

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetch(_ rawQuery: String, completion: @escaping (AHDLookupResult) -> Void) {
    cancel()
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      completion(AHDLookupResult(entry: nil, suggestions: []))
      return
    }

    let requestedGeneration = generation
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, requestedGeneration == self.generation,
        let definitionURL = Self.definitionURL(for: query)
      else { return }

      self.pendingWorkItem = nil
      let group = DispatchGroup()
      let parts = AHDResponseParts()
      func dataTask(for url: URL, store: @escaping (Data?) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        group.enter()
        return self.session.dataTask(with: request) { data, response, error in
          let status = (response as? HTTPURLResponse)?.statusCode
          store(error == nil && status == 200 ? data : nil)
          group.leave()
        }
      }

      var tasks = [dataTask(for: definitionURL, store: parts.setDefinitionData)]
      if query.count >= 3, let suggestionURL = Self.suggestionURL(for: query) {
        tasks.append(dataTask(for: suggestionURL, store: parts.setSuggestionData))
      }
      self.activeTasks = tasks
      tasks.forEach { $0.resume() }

      group.notify(queue: .main) { [weak self] in
        guard let self, requestedGeneration == self.generation else { return }
        self.activeTasks = []
        let data = parts.snapshot()
        completion(
          AHDLookupResult(
            entry: data.definition.flatMap(AHDResponseParser.entry),
            suggestions: data.suggestions.map(AHDResponseParser.suggestions) ?? []
          ))
      }
    }
    pendingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
  }

  func cancel() {
    generation += 1
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
    activeTasks.forEach { $0.cancel() }
    activeTasks = []
  }

  static func suggestionURL(for query: String) -> URL? {
    endpointURL(
      "https://www.ahdictionary.com/ajax/suggest.html",
      parameter: "query",
      value: query
    )
  }

  static func definitionURL(for query: String) -> URL? {
    endpointURL(
      "https://www.ahdictionary.com/word/search.html",
      parameter: "q",
      value: query
    )
  }

  private static func endpointURL(_ endpoint: String, parameter: String, value: String) -> URL? {
    guard var components = URLComponents(string: endpoint) else { return nil }
    components.queryItems = [URLQueryItem(name: parameter, value: value)]
    return components.url
  }
}
