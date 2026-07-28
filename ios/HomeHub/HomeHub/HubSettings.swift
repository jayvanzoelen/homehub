import Combine
import Foundation

enum HubAddressError: LocalizedError, Equatable {
    case empty
    case invalid
    case unsupportedScheme
    case missingHost
    case credentialsNotAllowed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter the address of the Home Hub server."
        case .invalid:
            return "That server address is not valid."
        case .unsupportedScheme:
            return "Use an http:// or https:// address."
        case .missingHost:
            return "The server address needs a host name or IP address."
        case .credentialsNotAllowed:
            return "Do not put a username or password in the server address."
        }
    }
}

enum HubAddress {
    static let suggestedAddress = "http://192.168.1.10:8787"

    static func normalize(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HubAddressError.empty
        }

        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate) else {
            throw HubAddressError.invalid
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw HubAddressError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw HubAddressError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw HubAddressError.credentialsNotAllowed
        }

        components.scheme = scheme
        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw HubAddressError.invalid
        }
        return url
    }

    static func endpoint(_ path: String, relativeTo baseURL: URL) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }
}

@MainActor
final class HubSettings: ObservableObject {
    private static let serverURLKey = "homehub.serverURL"
    private let defaults: UserDefaults

    @Published private(set) var serverURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.serverURLKey) {
            serverURL = try? HubAddress.normalize(stored)
        }
    }

    func save(serverURL: URL) {
        defaults.set(serverURL.absoluteString, forKey: Self.serverURLKey)
        self.serverURL = serverURL
    }

    func forgetServer() {
        defaults.removeObject(forKey: Self.serverURLKey)
        serverURL = nil
    }
}
