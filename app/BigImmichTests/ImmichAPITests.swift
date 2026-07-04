import Foundation
@testable import ImmichAPI
import Testing

private struct Ping: Decodable, Equatable {
    let ok: Bool
}

private final class StubExecutor: RequestExecuting, @unchecked Sendable {
    private var responses: [(Data, HTTPURLResponse)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = responses.removeFirst()
        return (next.0, next.1)
    }
}

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "http://immich.test/api")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func json(_ string: String) -> Data {
    Data(string.utf8)
}

private let apiKeyConfig = ImmichAPIConfig(baseURL: "http://immich.test", auth: .apiKey("secret"))

struct ImmichAPIAuthTests {
    @Test func sendsApiKeyHeader() async throws {
        let stub = StubExecutor([(json(#"{"ok":true}"#), response(200))])
        let api = ImmichAPI(executor: stub, configProvider: { apiKeyConfig })

        let ping: Ping = try await api.loadObject(path: "/api/ping", queryParams: [:])

        #expect(ping == Ping(ok: true))
        #expect(stub.requests.first?.value(forHTTPHeaderField: "x-api-key") == "secret")
    }

    @Test func missingConfigThrows() async throws {
        let api = ImmichAPI(executor: StubExecutor([]), configProvider: { nil })

        do {
            let _: Ping = try await api.loadObject(path: "/api/ping", queryParams: [:])
            Issue.record("expected missingConfig")
        } catch ImmichAPIError.missingConfig {}
    }

    @Test func retriesOnceAfterUnauthorized() async throws {
        let stub = StubExecutor([
            (Data(), response(401)),
            (json(#"{"ok":true}"#), response(200))
        ])
        let api = ImmichAPI(executor: stub, configProvider: { apiKeyConfig })

        let ping: Ping = try await api.loadObject(path: "/api/ping", queryParams: [:])

        #expect(ping == Ping(ok: true))
        #expect(stub.requests.count == 2)
    }

    @Test func mapsHttpErrorStatus() async throws {
        let stub = StubExecutor([(Data(), response(500))])
        let api = ImmichAPI(executor: stub, configProvider: { apiKeyConfig })

        do {
            let _: Ping = try await api.loadObject(path: "/api/ping", queryParams: [:])
            Issue.record("expected an http error")
        } catch let ImmichAPIError.httpErrorCode(statusCode) {
            #expect(statusCode == 500)
        }
    }

    @Test func mapsBadJson() async throws {
        let stub = StubExecutor([(json("not json"), response(200))])
        let api = ImmichAPI(executor: stub, configProvider: { apiKeyConfig })

        await #expect(throws: ImmichAPIError.self) {
            let _: Ping = try await api.loadObject(path: "/api/ping", queryParams: [:])
        }
    }

    @Test func loadArraySkipsInvalidElements() async throws {
        let stub = StubExecutor([
            (json(#"[{"ok":true},{"nope":1},{"ok":false}]"#), response(200))
        ])
        let api = ImmichAPI(executor: stub, configProvider: { apiKeyConfig })

        let pings: [Ping] = try await api.loadArray(path: "/api/pings", queryParams: [:])

        #expect(pings == [Ping(ok: true), Ping(ok: false)])
    }

    @Test func queryAuthIncludesApiKey() async throws {
        let api = ImmichAPI(executor: StubExecutor([]), configProvider: { apiKeyConfig })

        let url = try await api.getUrlWithQueryAuth(
            path: "/api/asset/1/thumbnail",
            queryParams: ["size": "preview"]
        )

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "apiKey", value: "secret")))
        #expect(query.contains(URLQueryItem(name: "size", value: "preview")))
    }
}
