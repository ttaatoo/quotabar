import Foundation

/// Popover switcher selection. Kept off `ProviderKind` so Settings panes,
/// refresh jobs, and clients stay provider-only.
enum PopoverTab: Equatable, Hashable, Identifiable, Sendable, Codable {
    case all
    case provider(ProviderKind)

    var id: String {
        switch self {
        case .all: return "all"
        case .provider(let provider): return provider.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .provider(let provider): return provider.title
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return "All"
        case .provider(let provider): return provider.shortTitle
        }
    }

    var provider: ProviderKind? {
        if case .provider(let provider) = self { return provider }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "all" {
            self = .all
            return
        }
        if let provider = ProviderKind(rawValue: raw) {
            self = .provider(provider)
            return
        }
        self = .all
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all:
            try container.encode("all")
        case .provider(let provider):
            try container.encode(provider.rawValue)
        }
    }
}
