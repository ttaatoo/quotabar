import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case cursor
    case chatgpt
    case glm
    case grok
    case opencodeGo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT"
        case .glm: return "GLM"
        case .grok: return "Grok"
        case .opencodeGo: return "OpenCode"
        }
    }

    /// Compact pill label. Five providers must still fit the frozen popover row.
    var shortTitle: String {
        switch self {
        case .opencodeGo: return "Go"
        default: return title
        }
    }

    /// Reserved popover slot 1 when that window is absent.
    var primaryWindowTitle: String {
        switch self {
        case .cursor: return "Cursor Models"
        case .chatgpt, .glm, .grok, .opencodeGo: return "Session"
        }
    }

    /// Reserved popover slot 2 when that window is absent.
    var secondaryWindowTitle: String {
        switch self {
        case .cursor: return "Other Models"
        case .chatgpt, .glm, .opencodeGo: return "Weekly"
        case .grok: return "Credits"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .cursor: return "square.grid.2x2"
        case .chatgpt: return "text.bubble"
        case .glm: return "hexagon"
        case .grok: return "sparkles"
        case .opencodeGo: return "terminal"
        }
    }

    var signInHint: String {
        switch self {
        case .cursor:
            return "Sign in to Cursor.app, or paste a WorkosCursorSessionToken cookie in Settings."
        case .chatgpt:
            return "Add a ChatGPT account in Settings to sign in with Codex in your browser."
        case .glm:
            return "Paste a z.ai / BigModel API key in Settings, or set Z_AI_API_KEY."
        case .grok:
            return "Add a Grok account in Settings to sign in with the Grok CLI in your browser."
        case .opencodeGo:
            return "Add an OpenCode Go API key in Settings, or set OPENCODE_GO_API_KEY / OPENCODE_API_KEY."
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case remaining
    case used

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: return "Remaining"
        case .used: return "Used"
        }
    }
}

enum GLMRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case global
    case china

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global: return "Global (api.z.ai)"
        case .china: return "China (open.bigmodel.cn)"
        }
    }

    var hostString: String {
        switch self {
        case .global: return "https://api.z.ai"
        case .china: return "https://open.bigmodel.cn"
        }
    }
}
