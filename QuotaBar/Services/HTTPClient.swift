import Foundation

enum HTTPClient {
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    /// Cookie-less session. `URLSession.shared` stores chatgpt.com `Set-Cookie`
    /// values in the process cookie jar, so a later account's Bearer request
    /// would send the previous account's session and come back 401 or as the
    /// wrong user. Every caller that needs a cookie passes it in `headers`.
    private static let session = makeSession(followRedirects: true)

    /// API-key clients (OpenCode Go) must not follow a rewritten host with the Bearer.
    private static let pinnedSession = makeSession(followRedirects: false)

    private static func makeSession(followRedirects: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = RedirectDelegate(followRedirects: followRedirects)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static func get(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 20,
        followRedirects: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        try await request(
            method: "GET",
            url: url,
            headers: headers,
            body: nil,
            timeout: timeout,
            followRedirects: followRedirects,
            contentType: nil
        )
    }

    static func postJSON(
        url: URL,
        headers: [String: String] = [:],
        body: [String: Any],
        timeout: TimeInterval = 20,
        followRedirects: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await request(
            method: "POST",
            url: url,
            headers: headers,
            body: data,
            timeout: timeout,
            followRedirects: followRedirects,
            contentType: "application/json"
        )
    }

    private static func request(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval,
        followRedirects: Bool,
        contentType: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let urlSession = followRedirects ? session : pinnedSession
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw QuotaError.network("Unexpected response from \(url.host ?? url.absoluteString).")
            }
            return (data, http)
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.network(error.localizedDescription)
        }
    }

    static func requireOK(_ response: HTTPURLResponse, data: Data, host: String) throws {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw QuotaError.unauthorized("\(host) rejected the session (\(response.statusCode)).")
        }
        guard (200...299).contains(response.statusCode) else {
            let snippet = String(data: data.prefix(180), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QuotaError.http(response.statusCode, snippet.isEmpty ? host : snippet)
        }
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(followRedirects ? request : nil)
    }
}
