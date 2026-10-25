import Foundation
import Testing
@testable import UsageBarCore

/// Stubs the network per host so tests can run in parallel without sharing state.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [URLRequest]] = [:]

    static func stub(host: String, _ reply: Reply) {
        lock.withLock { replies[host] = reply }
    }

    static func requests(for host: String) -> [URLRequest] {
        lock.withLock { seen[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let reply = Self.lock.withLock { () -> Reply? in
            Self.seen[host, default: []].append(request)
            return Self.replies[host]
        }
        guard let reply, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct HTTPClientTests {
    private func client(host: String, maxBytes: Int = 1_000_000) -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return HTTPClient(allowedHosts: [host], timeout: 5, maxBytes: maxBytes, configuration: configuration)
    }

    private func uniqueHost() -> String { "h\(UUID().uuidString.prefix(8).lowercased()).test" }

    @Test func successReturnsBodyAndSendsAuthAndPlainEncoding() throws {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init(headers: ["x-limit": "7"], body: Data("{\"ok\":true}".utf8)))
        let response = try #require(client(host: host).get(URL(string: "https://\(host)/v1/key")!, bearer: "secret-token"))

        #expect(String(data: response.body, encoding: .utf8) == "{\"ok\":true}")
        #expect(response.http.value(forHTTPHeaderField: "x-limit") == "7")
        let sent = try #require(StubProtocol.requests(for: host).first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(sent.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
    }

    @Test func plainHttpIsRefusedWithoutSendingAnything() {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init())
        #expect(client(host: host).get(URL(string: "http://\(host)/")!, bearer: "k") == nil)
        #expect(StubProtocol.requests(for: host).isEmpty)
    }

    @Test func hostsOutsideTheAllowlistAreRefusedWithoutSendingAnything() {
        let allowed = uniqueHost(), other = uniqueHost()
        StubProtocol.stub(host: other, .init())
        #expect(client(host: allowed).get(URL(string: "https://\(other)/")!, bearer: "k") == nil)
        #expect(StubProtocol.requests(for: other).isEmpty)
    }

    @Test func aLookalikeSubdomainIsNotAllowed() {
        let host = uniqueHost()
        let lookalike = "evil." + host
        StubProtocol.stub(host: lookalike, .init())
        #expect(client(host: host).get(URL(string: "https://\(lookalike)/")!, bearer: "k") == nil)
        #expect(StubProtocol.requests(for: lookalike).isEmpty)
    }

    @Test func nonOKStatusIsNoData() {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init(status: 500, body: Data("oops".utf8)))
        #expect(client(host: host).get(URL(string: "https://\(host)/")!, bearer: "k") == nil)
    }

    @Test func bodiesOverTheCapAreNoData() {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init(body: Data(repeating: 65, count: 100)))
        #expect(client(host: host, maxBytes: 10).get(URL(string: "https://\(host)/")!, bearer: "k") == nil)
    }

    @Test func aCallerCannotOverrideTheAuthorizationHeader() throws {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init(body: Data("{}".utf8)))
        _ = client(host: host).get(URL(string: "https://\(host)/")!, bearer: "real", headers: ["Authorization": "Bearer evil"])
        let sent = try #require(StubProtocol.requests(for: host).first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer real")
    }

    @Test func postSendsAJSONBody() throws {
        let host = uniqueHost()
        StubProtocol.stub(host: host, .init(body: Data("{}".utf8)))
        _ = client(host: host).post(URL(string: "https://\(host)/q")!, json: ["query": "x"], bearer: "k")
        let sent = try #require(StubProtocol.requests(for: host).first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func redirectsAreNeverFollowed() {
        let collector = HTTPClient.Collector(maxBytes: 100)
        let task = URLSession.shared.dataTask(with: URL(string: "https://example.test/")!)
        let redirect = HTTPURLResponse(url: URL(string: "https://example.test/")!, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://elsewhere.test/"])!
        var followed: URLRequest? = URLRequest(url: URL(string: "https://sentinel.test/")!)
        collector.urlSession(.shared, task: task, willPerformHTTPRedirection: redirect,
                             newRequest: URLRequest(url: URL(string: "https://elsewhere.test/")!)) { followed = $0 }
        #expect(followed == nil)
    }
}
