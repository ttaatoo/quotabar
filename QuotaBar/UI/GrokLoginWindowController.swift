import AppKit
import Darwin
import Foundation

enum GrokLoginOutcome: Equatable {
    case imported(email: String?)
    case relogged(email: String?)
    case cancelled
    case failed(String)
}

enum GrokLoginMode: Equatable {
    case addAccount(usesPrivateHome: Bool)
    case relogin(accountId: UUID, homePath: String?, usesAmbient: Bool)
}

@MainActor
final class GrokLoginPresenter {
    static let shared = GrokLoginPresenter()

    private var controller: GrokLoginWindowController?

    func begin(store: AppStore) {
        if let imported = store.importAmbientGrokAccountIfAvailable() {
            let email = store.settings.grokAccounts.first(where: { $0.id == imported })?.email
            presentImportedNotice(email: email)
            return
        }
        start(mode: .addAccount(usesPrivateHome: store.hasAmbientGrokAccount))
    }

    func beginRelogin(store: AppStore, accountId: UUID) {
        guard let account = store.settings.grokAccounts.first(where: { $0.id == accountId }) else {
            return
        }
        start(
            mode: .relogin(
                accountId: accountId,
                homePath: account.grokHomePath,
                usesAmbient: account.usesAmbientAuthFile
            )
        )
    }

    private func start(mode: GrokLoginMode) {
        if let controller, controller.isVisible {
            controller.show()
            return
        }
        let controller = GrokLoginWindowController(mode: mode) { [weak self] source, result in
            Task { @MainActor [self, source] in
                self?.handle(result, from: source)
            }
        }
        self.controller = controller
        controller.show()
    }

    private func handle(
        _ result: GrokLoginOutcome,
        from source: GrokLoginWindowController
    ) {
        if controller === source {
            controller = nil
        }
        switch result {
        case .imported(let email):
            presentImportedNotice(email: email)
        case .relogged(let email):
            presentReloggedNotice(email: email)
        case .cancelled:
            break
        case .failed(let message):
            let alert = NSAlert()
            alert.messageText = "Couldn’t finish Grok sign-in"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func presentImportedNotice(email: String?) {
        let alert = NSAlert()
        alert.messageText = "Grok account added"
        if let email, !email.isEmpty {
            alert.informativeText = "Imported \(email) from ~/.grok/auth.json. QuotaBar only reads that file."
        } else {
            alert.informativeText = "Imported the Grok CLI session from ~/.grok/auth.json. QuotaBar only reads that file."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentReloggedNotice(email: String?) {
        let alert = NSAlert()
        alert.messageText = "Grok account re-logged"
        if let email, !email.isEmpty {
            alert.informativeText = "Updated \(email). Other Grok accounts were not changed."
        } else {
            alert.informativeText = "Updated this account’s Grok home. Other Grok accounts were not changed."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Runs `grok login --oauth` (system browser). Does not embed a web view and never writes auth.json.
@MainActor
final class GrokLoginWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: (GrokLoginWindowController, GrokLoginOutcome) -> Void
    private let mode: GrokLoginMode
    private var pendingResult: GrokLoginOutcome?
    private var didTeardown = false
    private let session = GrokLoginSession()
    private var createdHomeThisSession: URL?

    private var statusField: NSTextField!
    private var detailField: NSTextField!
    private var spinner: NSProgressIndicator!
    private var cancelButton: NSButton!

    var isVisible: Bool { window?.isVisible == true }

    init(
        mode: GrokLoginMode,
        onFinish: @escaping (GrokLoginWindowController, GrokLoginOutcome) -> Void
    ) {
        self.mode = mode
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 168),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        switch mode {
        case .addAccount:
            window.title = "Add Grok account"
        case .relogin:
            window.title = "Re-login Grok account"
        }
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

        let detail: String
        switch mode {
        case .addAccount:
            detail = "QuotaBar is running `grok login --oauth` so the Grok CLI can open your default browser. Tokens stay in that Grok home."
        case .relogin:
            detail = "Re-logging only this account. Other Grok accounts and their Grok homes are left alone."
        }
        detailField = NSTextField(wrappingLabelWithString: detail)
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
        let homePath: String?
        switch mode {
        case .addAccount(let usesPrivateHome):
            if usesPrivateHome {
                let home = GrokAuth.makeManagedHomeURL()
                do {
                    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                } catch {
                    finish(.failed("Couldn’t create a private Grok home for this account."))
                    return
                }
                createdHomeThisSession = home
                homePath = home.path(percentEncoded: false)
            } else {
                homePath = GrokAuth.defaultHomeURL().path(percentEncoded: false)
            }
        case .relogin(_, let existingPath, let usesAmbient):
            if let existing = GrokAuth.homeURL(path: existingPath) {
                homePath = existing.path(percentEncoded: false)
            } else if usesAmbient {
                homePath = GrokAuth.defaultHomeURL().path(percentEncoded: false)
            } else {
                let home = GrokAuth.makeManagedHomeURL()
                do {
                    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                } catch {
                    finish(.failed("Couldn’t create a private Grok home for this account."))
                    return
                }
                createdHomeThisSession = home
                homePath = home.path(percentEncoded: false)
            }
        }

        Task { @MainActor [self] in
            let result = await session.run(homePath: homePath)
            self.handleSessionResult(result, homePath: homePath)
        }
    }

    private func handleSessionResult(_ result: GrokLoginSession.Result, homePath: String?) {
        switch result.outcome {
        case .success:
            let home = GrokAuth.homeURL(path: homePath) ?? GrokAuth.defaultHomeURL()
            let usedPrivateHome = createdHomeThisSession != nil || !GrokAuth.isAmbientHome(home)
            guard let credentials = GrokAuth.loadAuthFile(home: home) else {
                discardCreatedHomeIfNeeded()
                if usedPrivateHome, GrokAuth.loadAuthFile() != nil {
                    finish(.failed("grok login finished, but auth.json landed in ~/.grok instead of this account’s private GROK_HOME. Extra accounts would overwrite that file. Use one grok login account, or paste a SuperGrok bearer under Advanced."))
                    return
                }
                finish(.failed("grok login finished, but no readable auth.json was in that Grok home. QuotaBar does not write tokens."))
                return
            }
            let ambient = GrokAuth.isAmbientHome(home)
            let identity = GrokAccountIdentity.resolve(credentials: credentials).display
            switch mode {
            case .addAccount:
                let id = AppStore.shared.upsertGrokAccountFromHome(
                    homePath: home.path(percentEncoded: false),
                    email: identity,
                    ambient: !usedPrivateHome && ambient
                )
                if id == nil {
                    discardCreatedHomeIfNeeded()
                    finish(.failed("Signed in, but QuotaBar could not add the account."))
                    return
                }
                finish(.imported(email: identity))
            case .relogin(let accountId, _, let usesAmbient):
                AppStore.shared.applyGrokRelogin(
                    accountId: accountId,
                    homePath: home.path(percentEncoded: false),
                    email: identity,
                    ambient: usesAmbient || ambient
                )
                finish(.relogged(email: identity))
            }
        case .cancelled:
            discardCreatedHomeIfNeeded()
            finish(.cancelled)
        case .missingBinary:
            discardCreatedHomeIfNeeded()
            finish(.failed("The grok CLI was not found. Install Grok and make sure grok is on PATH (or at ~/.grok/bin/grok), then try Add account again. SuperGrok bearer paste remains under Advanced."))
        case .timedOut:
            discardCreatedHomeIfNeeded()
            finish(.failed("grok login timed out before the browser session finished."))
        case .launchFailed(let message):
            discardCreatedHomeIfNeeded()
            finish(.failed(message))
        case .failed(let status, let output):
            discardCreatedHomeIfNeeded()
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : "\n\n\(trimmed.prefix(600))"
            finish(.failed("grok login exited with status \(status).\(suffix)"))
        }
    }

    private func discardCreatedHomeIfNeeded() {
        guard let created = createdHomeThisSession else { return }
        GrokAuth.removeManagedHomeIfSafe(created.path(percentEncoded: false))
        createdHomeThisSession = nil
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

    private func finish(_ result: GrokLoginOutcome) {
        guard pendingResult == nil else { return }
        pendingResult = result
        if case .imported = result {
            setBusy(true, status: "Signed in. Adding account…")
        }
        if case .relogged = result {
            setBusy(true, status: "Signed in. Updating account…")
        }
        window?.close()
    }

    private func teardown() {
        guard !didTeardown else { return }
        didTeardown = true
        session.cancel()
    }
}

final class GrokLoginSession: @unchecked Sendable {
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
        env["PATH"] = GrokCLILocator.expandedPATH(environment: env)
        if let homePath, !homePath.isEmpty {
            env["GROK_HOME"] = homePath
        }

        guard let executable = GrokCLILocator.resolve(environment: env) else {
            return Result(outcome: .missingBinary, output: "")
        }

        var arguments = ["login", "--oauth"]
        var result = launch(executable: executable, arguments: arguments, environment: env, timeout: timeout)
        if shouldRetryWithoutOAuthFlag(result) {
            arguments = ["login"]
            result = launch(executable: executable, arguments: arguments, environment: env, timeout: timeout)
        }
        if shouldRetryAuthLogin(result) {
            arguments = ["auth", "login"]
            result = launch(executable: executable, arguments: arguments, environment: env, timeout: timeout)
        }
        return result
    }

    private func shouldRetryWithoutOAuthFlag(_ result: Result) -> Bool {
        switch result.outcome {
        case .failed:
            let lower = result.output.lowercased()
            return lower.contains("unknown option")
                || lower.contains("unrecognized option")
                || lower.contains("unexpected argument")
                || lower.contains("invalid option")
                || lower.contains("unknown flag")
                || lower.contains("unrecognized flag")
        default:
            return false
        }
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
