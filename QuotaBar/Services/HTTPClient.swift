import Foundation

enum HTTPClient {
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    static func get(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 20
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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
