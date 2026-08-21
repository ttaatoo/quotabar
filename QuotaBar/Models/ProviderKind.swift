import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case cursor
    case chatgpt
    case glm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT"
        case .glm: return "GLM"
        }
    }

    var shortTitle: String { title }

    var signInHint: String {
        switch self {
        case .cursor:
            return "Sign in to Cursor.app, or paste a WorkosCursorSessionToken cookie in Settings."
        case .chatgpt:
            return "Paste a chatgpt.com session cookie in Settings, or the conversation_limit JSON from DevTools."
        case .glm:
            return "Paste a z.ai / BigModel API key in Settings, or set Z_AI_API_KEY."
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

    var host: URL {
        switch self {
        case .global: return URL(string: "https://api.z.ai")!
        case .china: return URL(string: "https://open.bigmodel.cn")!
        }
    }
}
