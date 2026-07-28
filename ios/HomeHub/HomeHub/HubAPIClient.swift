import Foundation

struct HubAPIClient {
    let baseURL: URL
    var session: URLSession = .shared

    func status() async throws -> HubStatus {
        try await get(path: "api/status")
    }

    func setArmed(_ armed: Bool, pin: String) async throws -> ArmResponse {
        var fields = [("armed", armed ? "true" : "false")]
        if !pin.isEmpty {
            fields.append(("pin", pin))
        }
        return try await postForm(path: "api/security/arm", fields: fields)
    }

    func securityEvents(limit: Int = 40) async throws -> [SecurityEventItem] {
        var components = URLComponents(
            url: HubAddress.endpoint("api/security/events", relativeTo: baseURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else {
            throw HubAPIError.invalidResponse
        }
        let response: SecurityEventsResponse = try await get(url: url)
        return response.events
    }

    func uploadMotion(jpegData: Data) async throws -> MotionResponse {
        let body = MultipartBody()
            .addingField(name: "note", value: "Motion detected by iPad")
            .addingFile(
                name: "photo",
                filename: "motion.jpg",
                contentType: "image/jpeg",
                data: jpegData
            )
        return try await postMultipart(path: "api/security/motion", body: body)
    }

    func scan(jpegData: Data, details: ScanDetails) async throws -> ScanResponse {
        var body = MultipartBody()
            .addingField(name: "name", value: details.name)
            .addingField(name: "quantity", value: String(details.quantity))
            .addingField(name: "unit", value: details.unit)
            .addingField(name: "location", value: details.location.rawValue)
            .addingField(name: "suggest", value: details.requestSuggestion ? "true" : "false")

        if let expiresOn = details.expiresOn {
            body = body.addingField(name: "expires_on", value: Self.dayString(from: expiresOn))
        }
        body = body.addingFile(
            name: "photo",
            filename: "capture.jpg",
            contentType: "image/jpeg",
            data: jpegData
        )
        return try await postMultipart(path: "api/scan", body: body)
    }

    func confirmScan(photoPath: String, details: ScanDetails) async throws -> ScanResponse {
        var fields = [
            ("name", details.name),
            ("photo_path", photoPath),
            ("quantity", String(details.quantity)),
            ("unit", details.unit),
            ("location", details.location.rawValue),
        ]
        if let expiresOn = details.expiresOn {
            fields.append(("expires_on", Self.dayString(from: expiresOn)))
        }
        return try await postForm(path: "api/scan/confirm", fields: fields)
    }

    func mediaURL(for path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        try await get(url: HubAddress.endpoint(path, relativeTo: baseURL))
    }

    private func get<Response: Decodable>(url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    private func postForm<Response: Decodable>(
        path: String,
        fields: [(String, String)]
    ) async throws -> Response {
        var request = URLRequest(url: HubAddress.endpoint(path, relativeTo: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    private func postMultipart<Response: Decodable>(
        path: String,
        body: MultipartBody
    ) async throws -> Response {
        var request = URLRequest(url: HubAddress.endpoint(path, relativeTo: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body.encoded
        request.setValue(
            "multipart/form-data; boundary=\(body.boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data).detail) ?? ""
            throw HubAPIError.server(status: http.statusCode, message: detail)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HubAPIError.invalidResponse
        }
    }

    private static func dayString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct ServerError: Decodable {
    let detail: String
}

struct MultipartBody {
    fileprivate let boundary: String
    private let parts: [Part]

    init(boundary: String = "HomeHub-\(UUID().uuidString)") {
        self.boundary = boundary
        parts = []
    }

    private init(boundary: String, parts: [Part]) {
        self.boundary = boundary
        self.parts = parts
    }

    func addingField(name: String, value: String) -> MultipartBody {
        var copy = parts
        copy.append(
            Part(
                disposition: "form-data; name=\"\(Self.escaped(name))\"",
                contentType: nil,
                data: Data(value.utf8)
            )
        )
        return MultipartBody(boundary: boundary, parts: copy)
    }

    func addingFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) -> MultipartBody {
        var copy = parts
        copy.append(
            Part(
                disposition:
                    "form-data; name=\"\(Self.escaped(name))\"; "
                    + "filename=\"\(Self.escaped(filename))\"",
                contentType: contentType,
                data: data
            )
        )
        return MultipartBody(boundary: boundary, parts: copy)
    }

    fileprivate var encoded: Data {
        var result = Data()
        for part in parts {
            result.append("--\(boundary)\r\n")
            result.append("Content-Disposition: \(part.disposition)\r\n")
            if let contentType = part.contentType {
                result.append("Content-Type: \(contentType)\r\n")
            }
            result.append("\r\n")
            result.append(part.data)
            result.append("\r\n")
        }
        result.append("--\(boundary)--\r\n")
        return result
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private struct Part {
        let disposition: String
        let contentType: String?
        let data: Data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
