import Foundation

/// The only place the app talks to the network. A request is sent only if it is https
/// to an allowlisted host; redirects are never followed (so the Authorization header
/// cannot reach another host); responses are requested uncompressed; and size and time
/// are capped. Anything else (bad status, oversize, timeout, error) yields nil.
struct HTTPClient: Sendable {
    struct Response {
        let body: Data
        let http: HTTPURLResponse
    }

    /// Hosts the usage readers are allowed to contact.
    static let defaultAllowedHosts: Set<String> = [
        "openrouter.ai",
        "api.groq.com",
        "ollama.com",
        "api.cloudflare.com",
        "serviceusage.googleapis.com",
    ]

    static let shared = HTTPClient()

    let allowedHosts: Set<String>
    let timeout: TimeInterval
    let maxBytes: Int
    /// Injected in tests (to stub the transport); defaults to a cookie-less, cache-less session.
    private let configuration: URLSessionConfiguration

    init(
        allowedHosts: Set<String> = HTTPClient.defaultAllowedHosts,
        timeout: TimeInterval = 10,
        maxBytes: Int = 1_000_000,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.allowedHosts = allowedHosts
        self.timeout = timeout
        self.maxBytes = maxBytes
        self.configuration = configuration
    }

    func get(_ url: URL, bearer: String, headers: [String: String] = [:]) -> Response? {
        send(url, method: "GET", body: nil, bearer: bearer, headers: headers)
    }

    func post(_ url: URL, json: [String: Any], bearer: String) -> Response? {
        guard JSONSerialization.isValidJSONObject(json),
              let body = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return send(url, method: "POST", body: body, bearer: bearer, headers: ["Content-Type": "application/json"])
    }

    private func send(_ url: URL, method: String, body: Data?, bearer: String, headers: [String: String]) -> Response? {
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
        // A key or header value with a line break could smuggle extra headers.
        let values = [bearer] + headers.values
        guard !values.contains(where: { $0.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F } }) else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        guard let configuration = configuration.copy() as? URLSessionConfiguration else { return nil }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // Total deadlines, not just idle timeouts, so a slow-drip response cannot hold the connection open.
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        let collector = Collector(maxBytes: maxBytes)
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        session.dataTask(with: request).resume()
        guard collector.wait(timeout: timeout + 2),
              let http = collector.response, http.statusCode == 200,
              !collector.overflowed, collector.error == nil else { return nil }
        return Response(body: collector.data, http: http)
    }

    /// Gathers the body up to the size cap and refuses redirects.
    final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let maxBytes: Int
        private let done = DispatchSemaphore(value: 0)
        private(set) var data = Data()
        private(set) var response: HTTPURLResponse?
        private(set) var error: Error?
        private(set) var overflowed = false

        init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }

        func wait(timeout: TimeInterval) -> Bool {
            done.wait(timeout: .now() + timeout) == .success
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            self.response = response as? HTTPURLResponse
            if response.expectedContentLength > Int64(maxBytes) {
                overflowed = true
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            data.append(chunk)
            if data.count > maxBytes {
                overflowed = true
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            self.error = error
            done.signal()
        }
    }
}
