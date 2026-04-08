import Foundation
import KeychainHelper

public enum ImmichAPIError: Error, LocalizedError {
    case missingConfig
    case badUrl
    case badResponse
    case badJsonResponse(description: String)
    case httpErrorCode(statusCode: Int)
    case unknownError
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "missing configuration"
        case .badUrl:
            return "broken url (possibly wrong configuration)"
        case .badResponse:
            return "bad response"
        case .badJsonResponse(let description):
            return "unexpected json response: \(description)"
        case .httpErrorCode(let statusCode):
            return "http error code \(statusCode)"
        case .unknownError:
            return "Unknown error"
        case .unauthorized:
            return "unauthorized"
        }
    }
}

public struct ImmichAPIConfig {
    let baseURL: String
    let authMethod: ImmichAPIAuthMethod

    // api-key based auth
    let APIKey: String

    // email/passwoed based auth
    let email: String
    let password: String
}

// Create a session that never stores or sends cookies
let statelessSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .never  // do not accept cookies
    config.httpShouldSetCookies = false  // do not send cookies
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

class ImmichAPIClient {
    private var baseURL: String

    public init(baseURL: String) {
        self.baseURL = baseURL
    }

    public func getUrl(path: String, queryParams: [String: String]?) -> URL? {
        guard let loadedBaseURL = URL(string: baseURL) else { return nil }

        let fullURL = loadedBaseURL.appendingPathComponent(path)

        var components = URLComponents(
            url: fullURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = (queryParams ?? [:]).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return components.url!
    }

    private func prepareRequest(
        httpMethod: String,
        path: String,
        queryParams: [String: String]?,
        headers: [String: String]?,
        jsonPayload: [String: String]?
    ) async throws -> URLRequest {
        guard let url = getUrl(path: path, queryParams: queryParams) else {
            throw ImmichAPIError.badUrl
        }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod

        for (headerName, headerValue) in headers ?? [:] {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }

        if let jsonPayload {
            guard
                let jsonData = try? JSONSerialization.data(
                    withJSONObject: jsonPayload
                )
            else { throw ImmichAPIError.unknownError }

            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = jsonData
        }

        return request
    }

    private func request(
        httpMethod: String,
        path: String,
        queryParams: [String: String]?,
        headers: [String: String]?,
        jsonPayload: [String: String]?
    ) async throws -> Data {
        let request = try await prepareRequest(
            httpMethod: httpMethod,
            path: path,
            queryParams: queryParams,
            headers: headers,
            jsonPayload: jsonPayload
        )

        let (data, response) = try await statelessSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImmichAPIError.badResponse
        }
        guard httpResponse.statusCode != 401 else {
            throw ImmichAPIError.unauthorized
        }
        guard httpResponse.statusCode < 400 else {
            throw ImmichAPIError.httpErrorCode(
                statusCode: httpResponse.statusCode
            )
        }

        return data
    }

    private func getErrorMessage(error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return
                "Type mismatch for type \(type), codingPath: \(context.codingPath), debugDescription: \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return
                "Value not found for type \(type), codingPath: \(context.codingPath), debugDescription: \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return
                "Key '\(key.stringValue)' not found, codingPath: \(context.codingPath), debugDescription: \(context.debugDescription)"
        case .dataCorrupted(let context):
            return
                "Data corrupted, codingPath: \(context.codingPath), debugDescription: \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error)"
        }
    }

    public func loadObject<T: Decodable>(
        httpMethod: String,
        path: String,
        queryParams: [String: String]?,
        headers: [String: String]?,
        jsonPayload: [String: String]?
    ) async throws -> T {
        let data = try await request(
            httpMethod: httpMethod,
            path: path,
            queryParams: queryParams,
            headers: headers,
            jsonPayload: jsonPayload
        )

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw ImmichAPIError.badJsonResponse(
                description: getErrorMessage(error: decodingError)
            )
        }
    }

    public func loadArray<T: Decodable>(
        httpMethod: String,
        path: String,
        queryParams: [String: String]?,
        headers: [String: String]? = nil,
        jsonPayload: [String: String]? = nil
    ) async throws -> [T] {
        let data = try await request(
            httpMethod: httpMethod,
            path: path,
            queryParams: queryParams,
            headers: headers,
            jsonPayload: jsonPayload
        )

        do {
            // Decode using LossyArray (ignores elements on failure)
            return try JSONDecoder().decode(LossyArray<T>.self, from: data)
                .elements
        } catch let decodingError as DecodingError {
            throw ImmichAPIError.badJsonResponse(
                description: getErrorMessage(error: decodingError)
            )
        }
    }

    public func loadMedia(
        httpMethod: String,
        path: String,
        queryParams: [String: String]?,
        headers: [String: String]?,
        jsonPayload: [String: String]?
    ) async throws -> Data {
        var request = try await prepareRequest(
            httpMethod: httpMethod,
            path: path,
            queryParams: queryParams,
            headers: headers,
            jsonPayload: jsonPayload
        )
        request.cachePolicy = .returnCacheDataElseLoad

        let (data, response) = try await statelessSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImmichAPIError.badResponse
        }
        guard httpResponse.statusCode != 401 else {
            throw ImmichAPIError.unauthorized
        }
        guard httpResponse.statusCode < 400 else {
            throw ImmichAPIError.httpErrorCode(
                statusCode: httpResponse.statusCode
            )
        }
        return data
    }
}

public actor ImmichAPIAuthenticator {
    public static let shared = ImmichAPIAuthenticator()

    private var token: String?
    private var isAuthenticating = false
    private var waiters: [CheckedContinuation<String, Error>] = []

    private init() {}

    private struct LoginResponse: Codable {
        let accessToken: String
    }

    public func logout() async {
        self.token = nil
    }

    public func login(config: ImmichAPIConfig) async throws -> String {
        guard config.authMethod == .emailAndPassword else {
            throw ImmichAPIError.unknownError
        }  // this method supports email/pass auth only

        if let token {
            return token
        }

        if isAuthenticating {
            return try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let token = try await performLogin(config: config)
            self.token = token

            // resume all waiting callers
            waiters.forEach { $0.resume(returning: token) }
            waiters.removeAll()

            return token
        } catch {
            // propagate error to waiters
            waiters.forEach { $0.resume(throwing: error) }
            waiters.removeAll()
            throw error
        }
    }

    private func performLogin(config: ImmichAPIConfig) async throws -> String {
        let response: LoginResponse = try await ImmichAPIClient(
            baseURL: config.baseURL
        ).loadObject(
            httpMethod: "POST",
            path: "/api/auth/login",
            queryParams: nil,
            headers: nil,
            jsonPayload: ["email": config.email, "password": config.password],
        )
        return response.accessToken
    }
}

public actor ImmichAPI {
    public static let shared = ImmichAPI()

    private init() {}

    private func getConfig() -> ImmichAPIConfig? {
        guard let baseURL = KeychainHelper.loadImmichURL() else { return nil }
        let authMethod =
            KeychainHelper.loadImmichAPIAuthMethod()
            ?? ImmichAPIAuthMethod.apiKey

        switch authMethod {
        case .apiKey:
            guard let apiKey = KeychainHelper.loadImmichAPIKey() else {
                return nil
            }

            return ImmichAPIConfig(
                baseURL: baseURL,
                authMethod: .apiKey,
                APIKey: apiKey,
                email: "",
                password: "",
            )

        case .emailAndPassword:
            guard let email = KeychainHelper.loadImmichAuthEmail() else {
                return nil
            }
            guard let password = KeychainHelper.loadImmichAuthPassword() else {
                return nil
            }

            return ImmichAPIConfig(
                baseURL: baseURL,
                authMethod: .emailAndPassword,
                APIKey: "",
                email: email,
                password: password,
            )
        }
    }

    private func findAuthHeaders() async throws -> [String: String] {
        guard let config = getConfig() else { return [:] }

        switch config.authMethod {
        case .apiKey:
            return [
                "x-api-key": config.APIKey
            ]
        case .emailAndPassword:
            return [
                "x-immich-session-token":
                    try await ImmichAPIAuthenticator.shared.login(
                        config: config
                    )
            ]
        }
    }

    private func findAuthQueryParams() async throws -> [String: String] {
        guard let config = getConfig() else { return [:] }

        switch config.authMethod {
        case .apiKey:
            return [
                "apiKey": config.APIKey
            ]
        case .emailAndPassword:
            return [
                "sessionKey": try await ImmichAPIAuthenticator.shared.login(
                    config: config
                )
            ]
        }
    }

    public func loadObject<T: Decodable>(
        path: String,
        queryParams: [String: String]?
    ) async throws -> T {
        guard let config = getConfig() else {
            throw ImmichAPIError.missingConfig
        }

        do {
            return try await ImmichAPIClient(baseURL: config.baseURL)
                .loadObject(
                    httpMethod: "GET",
                    path: path,
                    queryParams: queryParams,
                    headers: await findAuthHeaders(),
                    jsonPayload: nil,
                )
        } catch ImmichAPIError.unauthorized {
            await ImmichAPIAuthenticator.shared.logout()

            return try await ImmichAPIClient(baseURL: config.baseURL)
                .loadObject(
                    httpMethod: "GET",
                    path: path,
                    queryParams: queryParams,
                    headers: await findAuthHeaders(),
                    jsonPayload: nil,
                )
        } catch {
            throw error
        }
    }

    public func loadArray<T: Decodable>(
        path: String,
        queryParams: [String: String]?
    ) async throws -> [T] {
        guard let config = getConfig() else {
            throw ImmichAPIError.missingConfig
        }

        do {
            return try await ImmichAPIClient(baseURL: config.baseURL)
                .loadArray(
                    httpMethod: "GET",
                    path: path,
                    queryParams: queryParams,
                    headers: await findAuthHeaders(),
                    jsonPayload: nil,
                )
        } catch ImmichAPIError.unauthorized {
            await ImmichAPIAuthenticator.shared.logout()

            return try await ImmichAPIClient(baseURL: config.baseURL)
                .loadArray(
                    httpMethod: "GET",
                    path: path,
                    queryParams: queryParams,
                    headers: await findAuthHeaders(),
                    jsonPayload: nil,
                )
        } catch {
            throw error
        }
    }

    public func loadMediaWithRetries(
        path: String,
        queryParams: [String: String]?,
        retries: Int
    ) async throws
        -> Data
    {
        var lastError: Error?

        for attempt in 1...retries {
            do {
                return try await loadMedia(path: path, queryParams: queryParams)
            } catch {
                lastError = error

                if attempt == retries {
                    throw error
                }

                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            }
        }

        // should never reach here, but required for compilation
        throw lastError ?? ImmichAPIError.unknownError
    }

    public func loadMedia(path: String, queryParams: [String: String]?)
        async throws -> Data
    {
        guard let config = getConfig() else {
            throw ImmichAPIError.missingConfig
        }

        do {
            return try await ImmichAPIClient(baseURL: config.baseURL).loadMedia(
                httpMethod: "GET",
                path: path,
                queryParams: queryParams,
                headers: await findAuthHeaders(),
                jsonPayload: nil,
            )
        } catch ImmichAPIError.unauthorized {
            await ImmichAPIAuthenticator.shared.logout()

            return try await ImmichAPIClient(baseURL: config.baseURL).loadMedia(
                httpMethod: "GET",
                path: path,
                queryParams: queryParams,
                headers: await findAuthHeaders(),
                jsonPayload: nil,
            )
        } catch {
            throw error
        }
    }

    public func getUrlWithQueryAuth(
        path: String,
        queryParams: [String: String]?
    ) async throws -> URL {
        // this method shouldn't be called as the first one,
        // so there's no need to catch 401 and log out user here
        guard let config = getConfig() else {
            throw ImmichAPIError.missingConfig
        }

        var urlQueryParams = try await findAuthQueryParams()
        if let queryParams {
            urlQueryParams = urlQueryParams.merging(queryParams) { (_, new) in
                new
            }
        }

        let playbackUrl = ImmichAPIClient(
            baseURL: config.baseURL
        ).getUrl(
            path: path,
            queryParams: urlQueryParams,
        )
        guard let playbackUrl else { throw ImmichAPIError.badUrl }

        return playbackUrl
    }
}
