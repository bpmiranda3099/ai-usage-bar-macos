import AppKit
import SwiftUI

/// A borderless, non-activating panel hosting SwiftUI content that applies
/// the real Liquid Glass material (`.glassEffect`) introduced in macOS 26+.
/// The panel itself just needs to be non-opaque so the glass effect can
/// sample what's behind it; the material/shape/border all come from
/// `.glassEffect()` in ContentView, matching the system's own Control
/// Center modules rather than the older NSVisualEffectView vibrancy.
final class UsagePanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>

    init<Content: View>(rootView: Content) {
        hostingView = NSHostingView(rootView: AnyView(rootView))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // The panel is sized explicitly (see applyContentSize); don't let the
        // hosting view resize the window on its own and shift the top edge.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = ContentView.cornerRadius
        hostingView.layer?.masksToBounds = true
        hostingView.autoresizingMask = [.width, .height]

        contentView = hostingView
        syncSizeToContent()
    }

    /// Recomputes the panel's frame to exactly match the current SwiftUI
    /// content size. Content changes (e.g. "Loading…" -> real data once the
    /// async fetch completes), so this must be called again before every
    /// show, not just once at init, or the window bounds stay stale/too
    /// small and clip content while showing a stray rectangular edge past
    /// the rounded glass shape.
    func syncSizeToContent() {
        // NSHostingView.fittingSize can report a stale/undersized value if
        // queried while the view's own frame is still small (e.g. the
        // panel's original 280x200 contentRect) — SwiftUI's layout pass
        // needs a generous proposal first to report its true intrinsic size.
        let measuringSize = NSSize(width: 1000, height: 1000)
        hostingView.frame = NSRect(origin: .zero, size: measuringSize)
        hostingView.layoutSubtreeIfNeeded()

        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else {
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            return
        }

        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)

        setContentSize(size)
        hostingView.frame = NSRect(origin: .zero, size: size)
        setFrameTopLeftPoint(topLeft)
        invalidateShadow()
    }

    /// Follows the SwiftUI content's size as it changes (including mid-animation),
    /// keeping the top edge pinned under the menu bar.
    func applyContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0,
              abs(size.width - frame.width) > 0.5 || abs(size.height - frame.height) > 0.5 else { return }
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        setContentSize(size)
        hostingView.frame = NSRect(origin: .zero, size: size)
        setFrameTopLeftPoint(topLeft)
    }

    override var canBecomeKey: Bool { true }
}
