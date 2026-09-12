import Foundation

enum GrokCLILocator {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let override = nonEmpty(environment["GROK_CLI_PATH"]),
           isExecutable(override, fileManager: fileManager) {
            return override
        }

        var seen = Set<String>()
        for directory in searchDirectories(environment: environment) {
            let candidate = (directory as NSString).appendingPathComponent("grok")
            let standardized = (candidate as NSString).standardizingPath
            if seen.contains(standardized) { continue }
            seen.insert(standardized)
            if isExecutable(standardized, fileManager: fileManager) {
                return standardized
            }
        }

        if let fromShell = loginShellWhich(environment: environment),
           isExecutable(fromShell, fileManager: fileManager) {
            return fromShell
        }
        return nil
    }

    static func expandedPATH(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var parts: [String] = []
        var seen = Set<String>()
        func append(_ raw: String) {
            let path = (raw as NSString).standardizingPath
            guard !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            parts.append(path)
        }

        for directory in searchDirectories(environment: environment) {
            append(directory)
        }
        if let existing = environment["PATH"] {
            for item in existing.split(separator: ":") {
                append(String(item))
            }
        }
        for fallback in ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            append(fallback)
        }
        return parts.joined(separator: ":")
    }

    private static func searchDirectories(environment: [String: String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        var directories: [String] = []

        directories.append("\(home)/.grok/bin")

        if let path = environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.grok/bin",
            "/opt/homebrew/opt/grok/bin",
            "/usr/local/opt/grok/bin"
        ])

        return directories
    }

    private static func loginShellWhich(environment: [String: String]) -> String? {
        let shell = nonEmpty(environment["SHELL"]) ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v grok"]
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func isExecutable(_ path: String, fileManager: FileManager) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
