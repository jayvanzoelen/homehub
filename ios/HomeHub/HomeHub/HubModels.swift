import Foundation

struct HubStatus: Decodable {
    let household: String
    let armed: Bool
    let activePersonID: Int?
    let visionEnabled: Bool
    let motionThreshold: Double
    let cooldownSeconds: Double

    enum CodingKeys: String, CodingKey {
        case household
        case armed
        case activePersonID = "active_person_id"
        case visionEnabled = "vision_enabled"
        case motionThreshold = "motion_threshold"
        case cooldownSeconds = "cooldown_seconds"
    }
}

struct ArmResponse: Decodable {
    let ok: Bool
    let armed: Bool
}

struct ScanResponse: Decodable {
    let ok: Bool
    let itemID: Int?
    let name: String?
    let needsName: Bool?
    let suggestedName: String?
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case itemID = "item_id"
        case name
        case needsName = "needs_name"
        case suggestedName = "suggested_name"
        case photoPath = "photo_path"
    }
}

struct MotionResponse: Decodable {
    let ok: Bool
    let ignored: Bool?
    let reason: String?
    let eventID: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case ignored
        case reason
        case eventID = "event_id"
    }
}

struct SecurityEventsResponse: Decodable {
    let events: [SecurityEventItem]
}

struct SecurityEventItem: Decodable, Identifiable {
    let id: Int
    let kind: String
    let note: String
    let createdAt: String
    let snapshotURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case note
        case createdAt = "created_at"
        case snapshotURL = "snapshot_url"
    }

    var displayDate: String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
        guard let date else {
            return createdAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

enum InventoryLocation: String, CaseIterable, Identifiable {
    case fridge
    case pantry
    case freezer
    case other

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ScanDetails {
    let name: String
    let quantity: Double
    let unit: String
    let location: InventoryLocation
    let expiresOn: Date?
    let requestSuggestion: Bool
}

enum HubAPIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Home Hub server returned an invalid response."
        case let .server(status, message):
            return message.isEmpty ? "The server returned error \(status)." : message
        case .invalidImage:
            return "The camera image could not be prepared."
        }
    }
}
