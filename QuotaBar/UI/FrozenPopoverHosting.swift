import AppKit
import SwiftUI

/// Menu-bar popover content controller. `fittingSize`, `intrinsicContentSize`,
/// and `preferredContentSize` are pinned to `Theme.popoverChromeSize` so a
/// provider switch cannot change the size NSPopover uses to re-anchor.
@MainActor
final class FrozenPopoverController: NSViewController {
    private let hosting: FrozenPopoverHostingController

    init(store: AppStore) {
        hosting = FrozenPopoverHostingController(store: store)
        super.init(nibName: nil, bundle: nil)
        super.preferredContentSize = Theme.popoverChromeSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredContentSize: NSSize {
        get { Theme.popoverChromeSize }
        set { /* frozen — do not let SwiftUI / AppKit rewrite this */ }
    }

    override func loadView() {
        let chrome = FrozenPopoverChromeView()
        view = chrome
        addChild(hosting)
        hosting.view.frame = NSRect(origin: .zero, size: Theme.popoverChromeSize)
        hosting.view.autoresizingMask = []
        hosting.view.clipsToBounds = true
        chrome.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        lockChromeFrames()
    }

    override func viewWillLayout() {
        lockChromeFrames()
        super.viewWillLayout()
        lockChromeFrames()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lockChromeFrames()
    }

    private func lockChromeFrames() {
        let size = Theme.popoverChromeSize
        if view.frame.size != size {
            view.setFrameSize(size)
        }
        let frame = NSRect(origin: .zero, size: size)
        if hosting.view.frame != frame {
            hosting.view.frame = frame
        }
    }
}

/// `NSHostingController` that never publishes a different preferred size.
@MainActor
final class FrozenPopoverHostingController: NSHostingController<PopoverView> {
    init(store: AppStore) {
        super.init(rootView: PopoverView(store: store))
        sizingOptions = []
        super.preferredContentSize = Theme.popoverChromeSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredContentSize: NSSize {
        get { Theme.popoverChromeSize }
        set { /* frozen */ }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sizingOptions = []
        view.clipsToBounds = true
        if view.frame.size != Theme.popoverChromeSize {
            view.setFrameSize(Theme.popoverChromeSize)
        }
    }

    override func viewWillLayout() {
        if view.frame.size != Theme.popoverChromeSize {
            view.setFrameSize(Theme.popoverChromeSize)
        }
        super.viewWillLayout()
        if view.frame.size != Theme.popoverChromeSize {
            view.setFrameSize(Theme.popoverChromeSize)
        }
    }
}

/// Root view NSPopover measures. Reports a constant size even when the
/// SwiftUI tree invalidates intrinsic content.
final class FrozenPopoverChromeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Theme.popoverChromeSize))
        clipsToBounds = true
        wantsLayer = true
        autoresizingMask = []
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize { Theme.popoverChromeSize }
    override var intrinsicContentSize: NSSize { Theme.popoverChromeSize }

    override func invalidateIntrinsicContentSize() {
        // Constant size. Swallow so NSPopover does not re-anchor on tab switch.
    }

    override func setFrameSize(_ newSize: NSSize) {
        let size = Theme.popoverChromeSize
        if bounds.size != size {
            super.setFrameSize(size)
        }
    }

    override func layout() {
        super.layout()
        let bounds = NSRect(origin: .zero, size: Theme.popoverChromeSize)
        for subview in subviews where subview.frame != bounds {
            subview.frame = bounds
        }
    }
}
