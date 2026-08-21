import AppKit
import WebKit

enum ChatGPTLoginResult {
    case succeeded(cookie: String, email: String?)
    case cancelled
}

@MainActor
final class ChatGPTLoginPresenter {
    static let shared = ChatGPTLoginPresenter()

    private var controller: ChatGPTLoginWindowController?

    func begin(store: AppStore) {
        if let controller, controller.isVisible {
            controller.show()
            return
        }
        let controller = ChatGPTLoginWindowController { [weak self] source, result in
            Task { @MainActor [self, store, source] in
                self?.handle(result, from: source, store: store)
            }
        }
        self.controller = controller
        controller.show()
    }

    private func handle(
        _ result: ChatGPTLoginResult,
        from source: ChatGPTLoginWindowController,
        store: AppStore
    ) {
        if controller === source {
            controller = nil
        }
        if case .succeeded(let cookie, let email) = result {
            store.upsertChatGPTAccount(cookie: cookie, email: email)
        }
    }
}

/// In-app ChatGPT sign-in. Each presentation uses a fresh non-persistent
/// `WKWebsiteDataStore` so a second Add account is not already the first session.
final class ChatGPTLoginWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: (ChatGPTLoginWindowController, ChatGPTLoginResult) -> Void
    private var pendingResult: ChatGPTLoginResult?
    private var didTeardown = false

    private var webView: WKWebView!
    private var statusField: NSTextField!
    private var spinner: NSProgressIndicator!
    private var pasteContainer: NSView!
    private var pasteField: NSSecureTextField!
    private var pasteButton: NSButton!
    private var pasteErrorField: NSTextField!

    private var popupWindows: [WKWebView: NSWindow] = [:]
    private var captureGeneration = 0
    private var isValidating = false
    private var lastProbedHeader: String?
    private var pollTimer: Timer?

    private let defaultStatus = "QuotaBar uses ~/.codex/auth.json from `codex login` the same way CodexBar does. Sign in here as a cookie fallback for that same usage API."

    var isVisible: Bool { window?.isVisible == true }

    init(onFinish: @escaping (ChatGPTLoginWindowController, ChatGPTLoginResult) -> Void) {
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add ChatGPT account"
        window.minSize = NSSize(width: 720, height: 520)
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
        if webView.url == nil {
            loadChatGPT()
        }
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if let web = popupWindows.first(where: { $0.value == closing })?.key {
            forgetPopup(web, closeWindow: false)
            return
        }
        guard closing == window else { return }
        teardown()
        let result = pendingResult ?? .cancelled
        pendingResult = nil
        onFinish(self, result)
    }

    // MARK: - Content

    private func buildContent() {
        let config = WKWebViewConfiguration()
        // Isolated, discarded after this window closes. Never default().
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.applicationNameForUserAgent = "Version/17.5 Safari/605.1.15"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.customUserAgent = HTTPClient.browserUserAgent
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        self.webView = webView

        let footer = makeFooter()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 760))
        container.autoresizingMask = [.width, .height]
        webView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addSubview(webView)
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        window?.contentView = container
        window?.setContentSize(NSSize(width: 920, height: 760))
    }

    private func makeFooter() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        statusField = NSTextField(labelWithString: defaultStatus)
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byWordWrapping
        statusField.maximumNumberOfLines = 2
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let pasteToggle = NSButton(
            title: "Paste a session cookie instead",
            target: self,
            action: #selector(togglePaste)
        )
        pasteToggle.bezelStyle = .recessed
        pasteToggle.isBordered = false
        pasteToggle.font = .systemFont(ofSize: 11)
        pasteToggle.contentTintColor = .linkColor

        pasteField = NSSecureTextField(string: "")
        pasteField.placeholderString = "__Secure-next-auth.session-token=… or a full Cookie header"
        pasteField.font = .systemFont(ofSize: 11)
        pasteField.target = self
        pasteField.action = #selector(submitPastedCookie)

        pasteButton = NSButton(title: "Use cookie", target: self, action: #selector(submitPastedCookie))
        pasteButton.bezelStyle = .rounded
        pasteButton.controlSize = .small

        pasteErrorField = NSTextField(labelWithString: "")
        pasteErrorField.font = .systemFont(ofSize: 11)
        pasteErrorField.textColor = .systemRed
        pasteErrorField.isHidden = true

        let pasteRow = NSStackView(views: [pasteField, pasteButton])
        pasteRow.orientation = .horizontal
        pasteRow.alignment = .centerY
        pasteRow.spacing = 8
        pasteField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let pasteStack = NSStackView(views: [pasteRow, pasteErrorField])
        pasteStack.orientation = .vertical
        pasteStack.alignment = .leading
        pasteStack.spacing = 4
        pasteStack.isHidden = true
        pasteContainer = pasteStack

        let statusRow = NSStackView(views: [spinner, statusField])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let stack = NSStackView(views: [statusRow, pasteToggle, pasteStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            pasteField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
        return bar
    }

    private func loadChatGPT() {
        guard let url = URL(string: "https://chatgpt.com") else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    @objc private func togglePaste() {
        pasteContainer.isHidden.toggle()
        if !pasteContainer.isHidden {
            window?.makeFirstResponder(pasteField)
        }
    }

    @objc private func submitPastedCookie() {
        let raw = pasteField.stringValue
        guard ChatGPTClient.normalizeCookie(raw) != nil else {
            showPasteError("Paste a chatgpt.com session cookie first.")
            return
        }
        pasteErrorField.isHidden = true
        setBusy(true, status: "Checking session…")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let info = try await ChatGPTClient.sessionInfo(cookie: raw)
                self.finish(.succeeded(cookie: raw, email: info.email))
            } catch {
                self.setBusy(false, status: self.defaultStatus)
                self.showPasteError("That cookie did not return a ChatGPT session.")
            }
        }
    }

    private func showPasteError(_ message: String) {
        pasteErrorField.stringValue = message
        pasteErrorField.isHidden = false
        if pasteContainer.isHidden {
            pasteContainer.isHidden = false
        }
    }

    private func setBusy(_ busy: Bool, status: String) {
        statusField.stringValue = status
        if busy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        pasteButton.isEnabled = !busy
        pasteField.isEnabled = !busy
    }

    // MARK: - Capture

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in
                self?.scheduleCapture(tokenRequired: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func scheduleCapture(tokenRequired: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleCapture(tokenRequired: tokenRequired)
            }
            return
        }
        captureGeneration += 1
        let generation = captureGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self = self else { return }
            guard generation == self.captureGeneration, self.pendingResult == nil else { return }
            Task { @MainActor [self] in
                await self.considerSessionCapture(tokenRequired: tokenRequired)
            }
        }
    }

    @MainActor
    private func considerSessionCapture(tokenRequired: Bool) async {
        guard pendingResult == nil, !isValidating else { return }
        let pageURL = webView.url
        let cookies = await cookiesFromAllStores()
        let hasToken = ChatGPTClient.hasSessionToken(in: cookies)
        if tokenRequired && !hasToken { return }
        if !hasToken && ChatGPTClient.isLikelyAuthURL(pageURL) { return }
        guard let header = ChatGPTClient.cookieHeader(from: cookies) else { return }
        if header == lastProbedHeader { return }

        lastProbedHeader = header
        isValidating = true
        if hasToken {
            setBusy(true, status: "Checking session…")
        }
        defer {
            isValidating = false
        }

        do {
            let info = try await ChatGPTClient.sessionInfo(cookie: header)
            finish(.succeeded(cookie: header, email: info.email))
        } catch {
            if pendingResult == nil && hasToken {
                setBusy(false, status: defaultStatus)
            }
        }
    }

    @MainActor
    private func cookiesFromAllStores() async -> [HTTPCookie] {
        let stores = uniqueCookieStores()

        var merged: [HTTPCookie] = []
        var seen = Set<String>()
        for store in stores {
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                store.getAllCookies { continuation.resume(returning: $0) }
            }
            for cookie in cookies {
                let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
                if seen.insert(key).inserted {
                    merged.append(cookie)
                }
            }
        }
        return merged
    }

    private func uniqueCookieStores() -> [WKHTTPCookieStore] {
        var stores = [webView.configuration.websiteDataStore.httpCookieStore]
        for child in popupWindows.keys {
            let store = child.configuration.websiteDataStore.httpCookieStore
            if !stores.contains(where: { $0 === store }) {
                stores.append(store)
            }
        }
        return stores
    }

    private func finish(_ result: ChatGPTLoginResult) {
        guard pendingResult == nil else { return }
        pendingResult = result
        if case .succeeded = result {
            setBusy(true, status: "Signed in. Adding account…")
        }
        window?.close()
    }

    private func teardown() {
        guard !didTeardown else { return }
        didTeardown = true
        captureGeneration += 1
        pollTimer?.invalidate()
        pollTimer = nil
        for store in uniqueCookieStores() {
            store.remove(self)
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        for (child, popup) in popupWindows {
            child.navigationDelegate = nil
            child.uiDelegate = nil
            popup.delegate = nil
            popup.close()
        }
        popupWindows.removeAll()
    }

    private func windowForWebView(_ webView: WKWebView) -> NSWindow? {
        popupWindows[webView] ?? window
    }

    private func forgetPopup(_ webView: WKWebView, closeWindow: Bool) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        if store !== self.webView.configuration.websiteDataStore.httpCookieStore {
            store.remove(self)
        }
        if let popup = popupWindows.removeValue(forKey: webView) {
            popup.delegate = nil
            if closeWindow {
                popup.close()
            }
        }
        scheduleCapture(tokenRequired: true)
    }
}

extension ChatGPTLoginWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let scheme = navigationAction.request.url?.scheme?.lowercased() {
            switch scheme {
            case "http", "https", "about", "blob":
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleCapture(tokenRequired: false)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        scheduleCapture(tokenRequired: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        statusField.stringValue = "Couldn’t load ChatGPT. Check your network, or paste a session cookie instead."
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView == self.webView {
            loadChatGPT()
        }
    }
}

extension ChatGPTLoginWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Keep OAuth popups on this add-flow's isolated store, not default().
        configuration.websiteDataStore = webView.configuration.websiteDataStore

        let child = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        child.customUserAgent = webView.customUserAgent
        if configuration.websiteDataStore !== webView.configuration.websiteDataStore {
            child.configuration.websiteDataStore.httpCookieStore.add(self)
        }

        let popup = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popup.title = "ChatGPT sign-in"
        popup.contentView = child
        popup.isReleasedWhenClosed = false
        popup.level = .floating
        popup.delegate = self
        popup.center()
        popup.makeKeyAndOrderFront(nil)
        popupWindows[child] = popup
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView != self.webView else { return }
        forgetPopup(webView, closeWindow: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "ChatGPT"
        alert.informativeText = message
        if let host = windowForWebView(webView) {
            alert.beginSheetModal(for: host) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "ChatGPT"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let host = windowForWebView(webView) {
            alert.beginSheetModal(for: host) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }
}

extension ChatGPTLoginWindowController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        DispatchQueue.main.async { [weak self] in
            self?.scheduleCapture(tokenRequired: true)
        }
    }
}
