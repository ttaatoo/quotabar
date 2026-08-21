import AppKit
import Darwin
import Foundation

enum CodexLoginOutcome: Equatable {
    case imported(email: String?)
    case cancelled
    case failed(String)
}

@MainActor
final class CodexLoginPresenter {
    static let shared = CodexLoginPresenter()

    private var controller: CodexLoginWindowController?

    func begin(store: AppStore) {
        if let imported = store.importAmbientCodexAccountIfAvailable() {
            let email = store.settings.chatgptAccounts.first(where: { $0.id == imported })?.email
            presentImportedNotice(email: email)
            return
        }
        if let controller, controller.isVisible {
            controller.show()
            return
        }
        let usesPrivateHome = store.hasAmbientCodexAccount
        let controller = CodexLoginWindowController(usesPrivateHome: usesPrivateHome) { [weak self] source, result in
            Task { @MainActor [self, source] in
                self?.handle(result, from: source)
            }
        }
        self.controller = controller
        controller.show()
    }

    private func handle(
        _ result: CodexLoginOutcome,
        from source: CodexLoginWindowController
    ) {
        if controller === source {
            controller = nil
        }
        switch result {
        case .imported(let email):
            presentImportedNotice(email: email)
        case .cancelled:
            break
        case .failed(let message):
            let alert = NSAlert()
            alert.messageText = "Couldn’t add ChatGPT account"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func presentImportedNotice(email: String?) {
        let alert = NSAlert()
        alert.messageText = "ChatGPT account added"
        if let email, !email.isEmpty {
            alert.informativeText = "Imported \(email) from ~/.codex/auth.json. QuotaBar only reads that file."
        } else {
            alert.informativeText = "Imported the Codex CLI session from ~/.codex/auth.json. QuotaBar only reads that file."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Runs `codex login` (system browser). Does not embed a web view and never writes auth.json.
@MainActor
final class CodexLoginWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: (CodexLoginWindowController, CodexLoginOutcome) -> Void
    private let usesPrivateHome: Bool
    private var pendingResult: CodexLoginOutcome?
    private var didTeardown = false
    private let session = CodexLoginSession()

    private var statusField: NSTextField!
    private var detailField: NSTextField!
    private var spinner: NSProgressIndicator!
    private var cancelButton: NSButton!

    var isVisible: Bool { window?.isVisible == true }

    init(
        usesPrivateHome: Bool,
        onFinish: @escaping (CodexLoginWindowController, CodexLoginOutcome) -> Void
    ) {
        self.usesPrivateHome = usesPrivateHome
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 168),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add ChatGPT account"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if pendingResult == nil, !session.isRunning {
            startLogin()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing == window else { return }
        session.cancel()
        teardown()
        let result = pendingResult ?? .cancelled
        pendingResult = nil
        onFinish(self, result)
    }

    private func buildContent() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 168))

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusField = NSTextField(labelWithString: "Finish sign-in in your browser…")
        statusField.font = .systemFont(ofSize: 13, weight: .semibold)
        statusField.translatesAutoresizingMaskIntoConstraints = false

        detailField = NSTextField(wrappingLabelWithString: "QuotaBar is running `codex login` so the Codex CLI can open your default browser. Tokens stay in that Codex home — QuotaBar only reads them.")
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(spinner)
        container.addSubview(statusField)
        container.addSubview(detailField)
        container.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),

            statusField.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
            statusField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            statusField.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),

            detailField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            detailField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            detailField.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),

            cancelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        window?.contentView = container
        window?.setContentSize(NSSize(width: 420, height: 168))
    }

    private func startLogin() {
        setBusy(true, status: "Finish sign-in in your browser…")
        let privateHome: URL?
        if usesPrivateHome {
            let home = CodexCLIAuth.makeManagedHomeURL()
            do {
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            } catch {
                finish(.failed("Couldn’t create a private Codex home for this account."))
                return
            }
            privateHome = home
        } else {
            privateHome = nil
        }

        Task { @MainActor [self] in
            let result = await session.run(homePath: privateHome?.path)
            self.handleSessionResult(result, privateHome: privateHome)
        }
    }

    private func handleSessionResult(_ result: CodexLoginSession.Result, privateHome: URL?) {
        switch result.outcome {
        case .success:
            let home = privateHome ?? CodexCLIAuth.defaultHomeURL()
            guard let tokens = CodexCLIAuth.read(home: home) else {
                if let privateHome {
                    CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
                }
                finish(.failed("codex login finished, but no readable auth.json was in that Codex home. QuotaBar does not write tokens."))
                return
            }
            let id = AppStore.shared.upsertChatGPTAccountFromCodexHome(
                homePath: home.path,
                email: tokens.email,
                ambient: privateHome == nil
            )
            if id == nil {
                if let privateHome {
                    CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
                }
                finish(.failed("Signed in, but QuotaBar could not add the account."))
                return
            }
            finish(.imported(email: tokens.email))
        case .cancelled:
            if let privateHome {
                CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
            }
            finish(.cancelled)
        case .missingBinary:
            if let privateHome {
                CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
            }
            finish(.failed("Codex CLI was not found. Install it (`npm i -g @openai/codex` or the ChatGPT desktop app), then run `codex login` in Terminal or try Add account again. Cookie paste remains under Advanced."))
        case .timedOut:
            if let privateHome {
                CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
            }
            finish(.failed("codex login timed out before the browser session finished."))
        case .launchFailed(let message):
            if let privateHome {
                CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
            }
            finish(.failed(message))
        case .failed(let status, let output):
            if let privateHome {
                CodexCLIAuth.removeManagedHomeIfSafe(privateHome.path)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : "\n\n\(trimmed.prefix(600))"
            finish(.failed("codex login exited with status \(status).\(suffix)"))
        }
    }

    @objc private func cancelTapped() {
        session.cancel()
        window?.close()
    }

    private func setBusy(_ busy: Bool, status: String) {
        statusField.stringValue = status
        if busy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        cancelButton.isEnabled = true
    }

    private func finish(_ result: CodexLoginOutcome) {
        guard pendingResult == nil else { return }
        pendingResult = result
        if case .imported = result {
            setBusy(true, status: "Signed in. Adding account…")
        }
        window?.close()
    }

    private func teardown() {
        guard !didTeardown else { return }
        didTeardown = true
        session.cancel()
    }
}

final class CodexLoginSession: @unchecked Sendable {
    struct Result: Equatable {
        enum Outcome: Equatable {
            case success
            case cancelled
            case timedOut
            case missingBinary
            case failed(status: Int32, output: String)
            case launchFailed(String)
        }

        var outcome: Outcome
        var output: String
    }

    private let lock = NSLock()
    private var process: Process?
    private var processGroup: pid_t?
    private var cancelled = false

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        let group = processGroup
        lock.unlock()
        terminate(running, processGroup: group)
    }

    func run(homePath: String?, timeout: TimeInterval = 900) async -> Result {
        await Task.detached(priority: .userInitiated) { [self] in
            self.runBlocking(homePath: homePath, timeout: timeout)
        }.value
    }

    private func runBlocking(homePath: String?, timeout: TimeInterval) -> Result {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CodexCLILocator.expandedPATH(environment: env)
        if let homePath, !homePath.isEmpty {
            env["CODEX_HOME"] = homePath
        }

        guard let executable = CodexCLILocator.resolve(environment: env) else {
            return Result(outcome: .missingBinary, output: "")
        }

        var arguments = ["login"]
        var result = launch(executable: executable, arguments: arguments, environment: env, timeout: timeout)
        if shouldRetryAuthLogin(result) {
            arguments = ["auth", "login"]
            result = launch(executable: executable, arguments: arguments, environment: env, timeout: timeout)
        }
        return result
    }

    private func shouldRetryAuthLogin(_ result: Result) -> Bool {
        switch result.outcome {
        case .failed:
            let lower = result.output.lowercased()
            return lower.contains("unknown command")
                || lower.contains("unrecognized subcommand")
                || lower.contains("unrecognized command")
                || lower.contains("invalid command")
                || lower.contains("no such command")
        default:
            return false
        }
    }

    private func launch(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> Result {
        lock.lock()
        if cancelled {
            lock.unlock()
            return Result(outcome: .cancelled, output: "")
        }
        lock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Result(outcome: .launchFailed(error.localizedDescription), output: "")
        }

        let pid = process.processIdentifier
        let group: pid_t? = setpgid(pid, pid) == 0 ? pid : nil
        lock.lock()
        self.process = process
        self.processGroup = group
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled {
            terminate(process, processGroup: group)
            return Result(outcome: .cancelled, output: "")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            lock.lock()
            let stop = cancelled
            lock.unlock()
            if stop {
                terminate(process, processGroup: group)
                return Result(outcome: .cancelled, output: combinedOutput(stdout: stdout, stderr: stderr))
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        if process.isRunning {
            terminate(process, processGroup: group)
            return Result(outcome: .timedOut, output: combinedOutput(stdout: stdout, stderr: stderr))
        }

        let output = combinedOutput(stdout: stdout, stderr: stderr)
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            return Result(outcome: .cancelled, output: output)
        }
        if process.terminationStatus == 0 {
            return Result(outcome: .success, output: output)
        }
        return Result(
            outcome: .failed(status: process.terminationStatus, output: output),
            output: output
        )
    }

    private func combinedOutput(stdout: Pipe, stderr: Pipe) -> String {
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let merged = [out, err].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return String(merged.prefix(4000))
    }

    private func terminate(_ process: Process?, processGroup: pid_t?) {
        if let pgid = processGroup {
            kill(-pgid, SIGTERM)
        }
        if let process, process.isRunning {
            process.terminate()
        }
        let deadline = Date().addingTimeInterval(2)
        while let process, process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let process, process.isRunning {
            if let pgid = processGroup {
                kill(-pgid, SIGKILL)
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
