import SwiftUI

public struct ContentView: View {
    public static let toggleDuration = Layout.toggleDuration
    /// Posted when a section toggles: userInfo "height" is the expected final
    /// height, "grow" says whether the panel should grow ahead of the animation.
    public static let toggleNotification = Notification.Name("ContentViewSectionToggled")
    public static let sizeNotification = Notification.Name("ContentViewSizeChanged")

    @EnvironmentObject var store: UsageStore
    /// Expanded state by section id; defaults come from UserDefaults, which every change is mirrored to.
    @State private var expanded: [String: Bool] = [:]
    @State private var sectionHeights: [String: CGFloat] = [:]
    private let sizeBox = SizeBox()

    private final class SizeBox {
        var size: CGSize = .zero
    }

    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded[id] ?? Self.savedExpansion(id) },
            set: { newValue in
                announceToggle(expanded: newValue, sectionHeight: sectionHeights[id] ?? 0)
                expanded[id] = newValue
                UserDefaults.standard.set(newValue, forKey: Self.expansionKey(id))
            }
        )
    }

    private static func expansionKey(_ id: String) -> String { "\(id)Expanded" }

    private static func savedExpansion(_ id: String) -> Bool {
        UserDefaults.standard.object(forKey: expansionKey(id)) as? Bool ?? true
    }

    /// Lets the panel grow to its final height before an expand animation
    /// starts (content is pinned to the top, so nothing shifts), and shrink
    /// only after a collapse animation ends.
    private func announceToggle(expanded: Bool, sectionHeight: CGFloat) {
        let current = sizeBox.size.height
        let target = expanded ? current + sectionHeight - 2 : current - sectionHeight + 2
        NotificationCenter.default.post(
            name: Self.toggleNotification,
            object: nil,
            userInfo: ["height": target, "grow": expanded]
        )
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .panelInset()
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider().panelInset()

            if store.sections.isEmpty {
                Text(store.isRefreshing ? "Loading…" : "No usage data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .panelInset()
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(store.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider().panelInset()
                    }
                    ProviderSectionView(
                        section: section,
                        now: now,
                        isExpanded: expansion(for: section.id),
                        onHeightChange: { sectionHeights[section.id] = $0 }
                    )
                }
            }

            Divider().panelInset()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .panelInset()
            .padding(.vertical, 10)
        }
        // Width of a fully expanded panel (padding + label + both meter columns),
        // so collapsing every section doesn't shrink the container.
        .frame(minWidth: 2 * Layout.inset + Layout.rowLabelWidth + 2 * MeterColumns.columnWidth + MeterColumns.columnSpacing, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        // Reported every frame while an animation runs, so the panel tracks
        // the content exactly instead of being resized separately.
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            sizeBox.size = size
            NotificationCenter.default.post(name: Self.sizeNotification, object: nil, userInfo: ["size": size])
        }
        // The panel can briefly be taller than the content mid-animation; pin the
        // content to the top so the header doesn't drift while sections animate.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack {
            Text("Usage")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 20)
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(Formatting.clockString(lastUpdated))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button {
                store.refresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
        }
    }
}
