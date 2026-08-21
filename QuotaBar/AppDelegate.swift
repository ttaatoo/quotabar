import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let store = AppStore.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        bind()
        store.start()
        renderStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.persistSecrets()
        store.persistSettings()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: StatusItemRenderer.itemWidth)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imageScaling = .scaleNone
            button.toolTip = "QuotaBar"
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = FrozenPopoverController(store: store)
        // Frozen after first setup. Tab switch, refresh, and objectWillChange
        // must not rewrite contentSize and must not call show() again.
        popover.contentSize = Theme.popoverChromeSize
        self.popover = popover
        paintPopoverChrome()
        popover.delegate = self
    }

    private func bind() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusItem()
                self?.paintPopoverChrome()
            }
            .store(in: &cancellables)
    }

    private func paintPopoverChrome() {
        guard let view = popover.contentViewController?.view else { return }
        let color = Theme.backgroundNSColor.cgColor
        func paint(_ target: NSView?) {
            guard let target else { return }
            target.appearance = NSAppearance(named: .darkAqua)
            target.wantsLayer = true
            target.layer?.backgroundColor = color
        }
        paint(view)
        paint(view.superview)
        view.subviews.forEach { paint($0) }
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let mode = store.settings.displayMode
        let text: String
        let warning: Bool

        switch store.selectedState {
        case .ready(let snapshot):
            if let remaining = snapshot.mostConstrainedRemaining {
                let displayed = mode == .remaining ? remaining : max(0, 100 - remaining)
                text = "\(Int(displayed.rounded()))%"
                warning = snapshot.isLow
            } else {
                text = "—"
                warning = false
            }
        case .signedOut, .failure:
            text = "—"
            warning = false
        case .idle, .loading:
            text = "···"
            warning = false
        }

        button.image = StatusItemRenderer.image(text: text, warning: warning)
        button.image?.isTemplate = false
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.startClock()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            paintPopoverChrome()
            startEventMonitor()
            Task { await store.refreshSelected() }
        }
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [self] in
                guard let self = self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        paintPopoverChrome()
    }

    func popoverDidClose(_ notification: Notification) {
        store.stopClock()
        stopEventMonitor()
    }
}
