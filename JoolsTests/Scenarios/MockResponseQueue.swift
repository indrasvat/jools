import Foundation

/// Scripted sequence of HTTP responses for scenario tests. Each
/// outbound request pops the next response off the queue. Scenarios
/// can also attach per-request assertions — e.g. "the third request
/// MUST carry a `createTime=` query param" — that fire when the
/// request is served.
///
/// Thread-safe via an internal lock because `URLProtocol.startLoading`
/// is called on the URL-loading system's queue, not the scenario's.
final class MockResponseQueue: @unchecked Sendable {
    enum Outcome {
        /// Return an HTTP response with body data.
        case respond(statusCode: Int, body: Data)
        /// Fail the request with a URLError (e.g. `.timedOut`).
        case fail(URLError.Code)
    }

    struct Step {
        let outcome: Outcome
        /// Optional assertion invoked with the outbound request.
        /// Runs on the URL-loading queue; throw to fail the scenario.
        let assert: (@Sendable (URLRequest) -> Void)?
    }

    private let lock = NSLock()
    private var steps: [Step] = []
    private var served: [URLRequest] = []
    private var unexpected: Int = 0

    /// Queue an HTTP response (status + body).
    func respond(
        status: Int = 200,
        body: Data,
        assert: (@Sendable (URLRequest) -> Void)? = nil
    ) {
        enqueue(Step(outcome: .respond(statusCode: status, body: body), assert: assert))
    }

    /// Queue a JSON response (string body).
    func respond(
        status: Int = 200,
        json: String,
        assert: (@Sendable (URLRequest) -> Void)? = nil
    ) {
        respond(status: status, body: Data(json.utf8), assert: assert)
    }

    /// Queue a URLError to simulate network failure (e.g. timeout).
    func fail(
        with code: URLError.Code,
        assert: (@Sendable (URLRequest) -> Void)? = nil
    ) {
        enqueue(Step(outcome: .fail(code), assert: assert))
    }

    /// Pop the next step, or return nil if the queue is exhausted.
    /// Unexpected requests after the scripted sequence are counted
    /// and available via `unexpectedCount`; the default in that case
    /// is to respond with an empty successful body so the scenario
    /// can still observe the "no more activity" steady state.
    func next(for request: URLRequest) -> Step? {
        lock.lock()
        defer { lock.unlock() }
        served.append(request)
        guard !steps.isEmpty else {
            unexpected += 1
            return nil
        }
        return steps.removeFirst()
    }

    var servedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return served
    }

    var remainingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return steps.count
    }

    var unexpectedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return unexpected
    }

    private func enqueue(_ step: Step) {
        lock.lock()
        defer { lock.unlock() }
        steps.append(step)
    }
}

/// `URLProtocol` that serves responses from a `MockResponseQueue`.
/// The queue is assigned on the URLSessionConfiguration that the
/// `APIClient` uses, so every request the client makes is routed
/// here.
final class ScenarioURLProtocol: URLProtocol, @unchecked Sendable {
    /// Queue shared across all in-flight protocol instances for a
    /// given scenario. `nonisolated(unsafe)` because `URLProtocol`
    /// subclasses don't play nicely with actor isolation and we
    /// serialise access via `MockResponseQueue`'s own lock.
    nonisolated(unsafe) static var queue: MockResponseQueue?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let queue = Self.queue else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        guard let step = queue.next(for: request) else {
            // Unexpected extra request — respond with an empty 200
            // so the scenario can still observe steady state without
            // timing out the URL-loading system. Scenarios should
            // assert on `queue.unexpectedCount == 0` at the end.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"activities\":[]}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        step.assert?(request)

        switch step.outcome {
        case .respond(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}
