import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case cursor
    case chatgpt
    case glm
    case grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT"
        case .glm: return "GLM"
        case .grok: return "Grok"
        }
    }

    var shortTitle: String { title }

    /// Reserved popover slot 1 when that window is absent.
    var primaryWindowTitle: String {
        switch self {
        case .cursor: return "Cursor Models"
        case .chatgpt, .glm, .grok: return "Session"
        }
    }

    /// Reserved popover slot 2 when that window is absent.
    var secondaryWindowTitle: String {
        switch self {
        case .cursor: return "Other Models"
        case .chatgpt, .glm: return "Weekly"
        case .grok: return "Credits"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .cursor: return "square.grid.2x2"
        case .chatgpt: return "text.bubble"
        case .glm: return "hexagon"
        case .grok: return "sparkles"
        }
    }

    var signInHint: String {
        switch self {
        case .cursor:
            return "Sign in to Cursor.app, or paste a WorkosCursorSessionToken cookie in Settings."
        case .chatgpt:
            return "Add a ChatGPT account in Settings to run `codex login` in your default browser, or paste a session cookie / usage JSON under Advanced."
        case .glm:
            return "Paste a z.ai / BigModel API key in Settings, or set Z_AI_API_KEY."
        case .grok:
            return GrokAuth.signInHint
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
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

enum GLMRegion: String, Codable, CaseIterable, Identifiable {
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
