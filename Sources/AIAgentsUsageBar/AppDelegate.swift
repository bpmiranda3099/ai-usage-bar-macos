import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: UsagePanel!
    private var clickOutsideMonitor: Any?
    private var lastClosedTimestamp: TimeInterval = 0
    let store = UsageStore()
    private var lastContentSize: CGSize?
    private var isToggleAnimating = false
    private var settleWork: DispatchWorkItem?
    private var rateMeterTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusBarIcon.make()
            button.action = #selector(togglePanel)
            button.target = self
        }

        panel = UsagePanel(rootView: ContentView().environmentObject(store))

        NotificationCenter.default.addObserver(forName: ContentView.sizeNotification, object: nil, queue: .main) { [weak self] note in
            guard let size = note.userInfo?["size"] as? CGSize else { return }
            MainActor.assumeIsolated {
                self?.lastContentSize = size
                if self?.isToggleAnimating == false {
                    self?.panel.applyContentSize(size)
                }
            }
        }

        NotificationCenter.default.addObserver(forName: ContentView.toggleNotification, object: nil, queue: .main) { [weak self] note in
            guard let height = note.userInfo?["height"] as? CGFloat,
                  let grow = note.userInfo?["grow"] as? Bool else { return }
            MainActor.assumeIsolated {
                self?.handleToggle(targetHeight: height, grow: grow)
            }
        }

        // Ensure panel closes whenever it loses focus, screen sleeps, or system locks
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }

        NotificationCenter.default.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }

        NotificationCenter.default.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    /// While an accordion animates, the panel is not resized per frame: it grows
    /// up front for an expand and snaps to the final size once the animation ends.
    private func handleToggle(targetHeight: CGFloat, grow: Bool) {
        isToggleAnimating = true
        if grow {
            panel.applyContentSize(NSSize(width: panel.frame.width, height: targetHeight))
        }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isToggleAnimating = false
            if let size = self.lastContentSize {
                self.panel.applyContentSize(size)
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ContentView.toggleDuration + 0.05, execute: work)
    }

    @objc private func togglePanel() {
        let now = ProcessInfo.processInfo.systemUptime
        // Prevent immediate re-opening if click-outside monitor already handled closing
        if now - lastClosedTimestamp < 0.25 {
            return
        }

        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        // Clean up any stale monitor
        removeClickOutsideMonitor()

        panel.syncSizeToContent()

        let buttonBounds = button.bounds
        let buttonScreenRect = buttonWindow.convertToScreen(button.convert(buttonBounds, to: nil))
        let panelSize = panel.frame.size

        // Clamp to screen visible frame to avoid offscreen placement
        let targetScreen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        var originX = buttonScreenRect.midX - panelSize.width / 2
        var originY = buttonScreenRect.minY - panelSize.height - 6

        originX = max(visibleFrame.minX + 8, min(originX, visibleFrame.maxX - panelSize.width - 8))
        originY = max(visibleFrame.minY + 8, originY)

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.makeKeyAndOrderFront(nil)
        store.refreshRateMeters()
        rateMeterTimer?.invalidate()
        rateMeterTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refreshRateMeters() }
        }
        NSApp.activate(ignoringOtherApps: true)

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            // Ignore click if it was inside the status button itself (let button action toggle)
            let mouseLoc = NSEvent.mouseLocation
            if buttonScreenRect.contains(mouseLoc) {
                return
            }
            self.closePanel()
        }
    }

    private func closePanel() {
        guard panel.isVisible else {
            removeClickOutsideMonitor()
            return
        }
        lastClosedTimestamp = ProcessInfo.processInfo.systemUptime
        panel.orderOut(nil)
        rateMeterTimer?.invalidate()
        rateMeterTimer = nil
        removeClickOutsideMonitor()
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
