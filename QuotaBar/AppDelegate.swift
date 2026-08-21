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
    private var lastIntrinsicSize = NSSize(width: Theme.popoverWidth, height: Theme.popoverCompactHeight)

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        // Reserved slots keep height stable; animating contentSize still rubber-bands on tab switch.
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(
            rootView: PopoverView(store: store, onIntrinsicSizeChange: { [weak self] size in
                Task { @MainActor [self] in
                    guard let self = self else { return }
                    self.applyPopoverContentSize(size)
                }
            })
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        self.popover = popover
        // Hug the SwiftUI card. A tall placeholder (e.g. 420) leaves empty chrome
        // above/below because NSPopover does not shrink on intrinsicContentSize alone.
        popover.contentSize = lastIntrinsicSize
        popover.contentViewController = hosting
        paintPopoverChrome()
        popover.delegate = self
    }

    private func bind() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusItem()
                self?.schedulePopoverResize()
            }
            .store(in: &cancellables)
    }

    private func schedulePopoverResize() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.applyPopoverContentSize(self.lastIntrinsicSize)
            self.paintPopoverChrome()
        }
    }

    private func applyPopoverContentSize(_ size: CGSize) {
        let reported = ceil(size.height)
        guard reported > 1 else { return }
        // Snap near the reserved-slot height so leftover 1pt layout jitter
        // does not rewrite contentSize (and bounce) on every tab switch.
        let height: CGFloat
        if abs(reported - Theme.popoverCompactHeight) < 4 {
            height = Theme.popoverCompactHeight
        } else {
            height = max(reported, Theme.popoverCompactHeight)
        }
        let next = NSSize(width: Theme.popoverWidth, height: height)
        lastIntrinsicSize = next
        if abs(popover.contentSize.height - next.height) > 0.5
            || abs(popover.contentSize.width - next.width) > 0.5 {
            popover.contentSize = next
        }
        paintPopoverChrome()
    }

    private func paintPopoverChrome() {
        guard let view = popover.contentViewController?.view else { return }
        let color = Theme.backgroundNSColor.cgColor
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = color
        if let parent = view.superview {
            parent.appearance = NSAppearance(named: .darkAqua)
            parent.wantsLayer = true
            parent.layer?.backgroundColor = color
        }
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
            applyPopoverContentSize(lastIntrinsicSize)
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
        applyPopoverContentSize(lastIntrinsicSize)
        paintPopoverChrome()
    }

    func popoverDidClose(_ notification: Notification) {
        store.stopClock()
        stopEventMonitor()
    }
}
