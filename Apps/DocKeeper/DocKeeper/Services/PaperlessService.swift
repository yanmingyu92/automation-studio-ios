import Foundation

enum PaperlessConfiguration {
    static let serverURLKey = "paperless.serverURL"

    static var serverURL: URL? {
        guard let value = UserDefaults.standard.string(forKey: serverURLKey) else { return nil }
        return try? PaperlessService.validatedServerURL(from: value)
    }

    static func saveServerURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: serverURLKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: serverURLKey)
    }
}

enum PaperlessError: LocalizedError {
    case invalidURL(String)
    case notConfigured
    case httpStatus(Int, String)
    case invalidResponse
    case emptyUploadResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let message), .httpStatus(_, let message): message
        case .notConfigured: "Add a server URL and API token before connecting to Paperless-ngx."
        case .invalidResponse: "The server returned a response DocKeeper did not recognize."
        case .emptyUploadResponse: "Paperless accepted the request but did not return a processing task identifier."
        }
    }
}

struct PaperlessService: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    static func validatedServerURL(from string: String) throws -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw PaperlessError.invalidURL("Enter a complete server URL, such as https://paperless.example.com.")
        }
        guard scheme == "https" || (scheme == "http" && isLocalHost(host)) else {
            throw PaperlessError.invalidURL("Use HTTPS. Plain HTTP is allowed only for localhost, .local, and private-network servers.")
        }
        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw PaperlessError.invalidURL("The server URL is invalid.")
        }
        return url
    }

    func testConnection(serverURL: URL, token: String) async throws {
        var components = URLComponents(url: endpoint(serverURL, "api/documents/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "page_size", value: "1")]
        guard let url = components?.url else { throw PaperlessError.invalidResponse }
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["results"] != nil || object["count"] != nil else {
            throw PaperlessError.invalidResponse
        }
    }

    func uploadDocument(
        _ pdfData: Data,
        filename: String,
        title: String,
        serverURL: URL,
        token: String
    ) async throws -> String {
        let boundary = "DocKeeper-\(UUID().uuidString)"
        var request = authorizedRequest(url: endpoint(serverURL, "api/documents/post_document/"), token: token)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(name: "title", value: title, boundary: boundary, to: &body)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"document\"; filename=\"\(safeFilename(filename))\"\r\n".utf8))
        body.append(Data("Content-Type: application/pdf\r\n\r\n".utf8))
        body.append(pdfData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if let taskID = try? JSONDecoder().decode(String.self, from: data), !taskID.isEmpty {
            return taskID
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let taskID = (object["task_id"] ?? object["task"]) as? String,
           !taskID.isEmpty {
            return taskID
        }
        throw PaperlessError.emptyUploadResponse
    }

    private func endpoint(_ base: URL, _ path: String) -> URL {
        path.split(separator: "/").reduce(base) { url, component in
            url.appendingPathComponent(String(component))
        }.appendingPathComponent("", isDirectory: true)
    }

    private func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw PaperlessError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = serverMessage(from: data)
            let message: String
            switch http.statusCode {
            case 401: message = "Paperless rejected the API token. \(detail)"
            case 403: message = "The token does not have permission for this request. \(detail)"
            case 413: message = "Paperless rejected the PDF because it is too large."
            case 429: message = "Paperless is receiving too many requests. Try again later."
            default: message = "Paperless returned HTTP \(http.statusCode). \(detail)"
            }
            throw PaperlessError.httpStatus(http.statusCode, message.trimmingCharacters(in: .whitespaces))
        }
    }

    private func serverMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let value = object["detail"] ?? object["error"] ?? object["document"]
            if let message = value as? String { return String(message.prefix(500)) }
            if let messages = value as? [String] { return String(messages.joined(separator: " ").prefix(500)) }
        }
        let text = String(decoding: data.prefix(500), as: UTF8.self)
        return text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private func appendFormField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    private func safeFilename(_ filename: String) -> String {
        let cleaned = filename.replacingOccurrences(of: "[\"\\\r\n]", with: "_", options: .regularExpression)
        return cleaned.isEmpty ? "document.pdf" : cleaned
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        let isUnqualifiedHostname = !lowercased.contains(".") && !lowercased.contains(":")
        if lowercased == "localhost" || isUnqualifiedHostname || lowercased.hasSuffix(".local") || lowercased == "::1" || lowercased.hasPrefix("fe80:") {
            return true
        }
        let parts = lowercased.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }
}
