import SwiftUI

struct ContentView: View {
    static let cornerRadius: CGFloat = 20

    /// Accordion state, persisted in UserDefaults so it survives restarts and redeploys.
    static let toggleDuration: TimeInterval = 0.25
    static let toggleAnimation = Animation.easeInOut(duration: toggleDuration)
    /// Posted when a section toggles: userInfo "height" is the expected final
    /// height, "grow" says whether the panel should grow ahead of the animation.
    static let toggleNotification = Notification.Name("ContentViewSectionToggled")
    static let sizeNotification = Notification.Name("ContentViewSizeChanged")

    private static func loadExpanded(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    @EnvironmentObject var store: UsageStore
    // @State (not @AppStorage) so the toggle animates; changes are mirrored to UserDefaults below.
    @State private var antigravityExpanded = Self.loadExpanded("antigravityExpanded")
    @State private var claudeExpanded = Self.loadExpanded("claudeExpanded")
    @State private var antigravityHeight: CGFloat = 0
    @State private var claudeHeight: CGFloat = 0
    @State private var openCodeExpanded = Self.loadExpanded("openCodeExpanded")
    @State private var openCodeHeight: CGFloat = 0
    private let sizeBox = SizeBox()

    private final class SizeBox {
        var size: CGSize = .zero
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
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

    private static let statLabelWidth: CGFloat = 144

    /// Stat columns with the model name in front of the bars; the reset line
    /// is indented to stay aligned under them.
    private func labeledStats(_ entry: UsageEntry, label: String? = nil, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(label ?? entry.id.replacingOccurrences(of: "models", with: "Models"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.statLabelWidth, alignment: .leading)
                    .help(entry.models.joined(separator: "\n"))
                UsageStatColumns(entry: entry)
            }
            if entry.fiveHourReset != nil || entry.weeklyReset != nil {
                UsageResetLines(entry: entry, now: now)
                    .padding(.leading, Self.statLabelWidth)
            }
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            if store.entries.isEmpty {
                Text(store.isRefreshing ? "Loading…" : "No usage data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                let antigravity = store.entries.first(where: { $0.id == "Gemini Models" })
                let agyClaude = store.entries.first(where: { $0.id == "Claude and GPT models" })
                let claudeCode = store.entries.first(where: { $0.id == "Claude and GPT models-claude-code" })
                // Extra Gemini models (e.g. Gemini 4 Argon) belong to the Antigravity block.
                let antigravityExtras = store.entries.filter {
                    $0.tintName == "antigravity" && $0.id != "Gemini Models"
                }
                // Per-model weekly limits Claude Code reports on some plans (e.g. Fable).
                let claudeCodeExtras = store.entries.filter { $0.id.hasPrefix("Claude and GPT models-claude-code-") }
                let openCodeEntries = store.entries.filter { $0.id.hasPrefix("opencode-") }
                let extraIDs = Set((antigravityExtras + claudeCodeExtras + openCodeEntries).map(\.id))
                let others = store.entries.filter {
                    $0.id != "Gemini Models" && $0.id != "Claude and GPT models" && $0.id != "Claude and GPT models-claude-code"
                        && !extraIDs.contains($0.id)
                }

                if let antigravity {
                    UsageRowView(entry: antigravity, now: now, showsStats: false, isExpanded: $antigravityExpanded)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, antigravityExpanded ? 12 : 10)

                    CollapsibleSection(isExpanded: antigravityExpanded, onHeightChange: { antigravityHeight = $0 }) {
                        VStack(alignment: .leading, spacing: 0) {
                        labeledStats(antigravity, now: now)
                            .padding(.horizontal, 16)
                            .padding(.bottom, agyClaude == nil && antigravityExtras.isEmpty ? 10 : 8)

                        if let agyClaude {
                            labeledStats(agyClaude, now: now)
                                .padding(.horizontal, 16)
                                .padding(.bottom, antigravityExtras.isEmpty ? 10 : 8)
                        }

                        ForEach(antigravityExtras) { extra in
                            labeledStats(extra, now: now)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                        }
                        }
                    }
                }

                if let claudeCode {
                    if antigravity != nil {
                        Divider().padding(.horizontal, 16)
                    }
                    UsageRowView(entry: claudeCode, now: now, showsStats: false, isExpanded: $claudeExpanded)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, claudeExpanded ? 12 : 10)

                    CollapsibleSection(isExpanded: claudeExpanded, onHeightChange: { claudeHeight = $0 }) {
                        VStack(alignment: .leading, spacing: 0) {
                        labeledStats(claudeCode, label: "Claude Models", now: now)
                            .padding(.horizontal, 16)
                            .padding(.bottom, claudeCodeExtras.isEmpty ? 10 : 8)

                        ForEach(claudeCodeExtras) { extra in
                            labeledStats(extra, label: "Claude \(extra.displayName)", now: now)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                        }
                        }
                    }
                }

                if !openCodeEntries.isEmpty {
                    if antigravity != nil || claudeCode != nil {
                        Divider().padding(.horizontal, 16)
                    }
                    UsageRowView(entry: UsageEntry.openCodeHeader, now: now, showsStats: false, isExpanded: $openCodeExpanded)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, openCodeExpanded ? 12 : 10)

                    CollapsibleSection(isExpanded: openCodeExpanded, onHeightChange: { openCodeHeight = $0 }) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(openCodeEntries.enumerated()), id: \.element.id) { index, entry in
                                labeledStats(entry, label: entry.displayName, now: now)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, index == openCodeEntries.count - 1 ? 10 : 8)
                            }
                        }
                    }
                }

                ForEach(Array(others.enumerated()), id: \.element.id) { index, entry in
                    if antigravity != nil || claudeCode != nil || !openCodeEntries.isEmpty || index > 0 {
                        Divider().padding(.horizontal, 16)
                    }
                    UsageRowView(entry: entry, now: now)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }

            Divider()
                .padding(.horizontal, 16)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        // Width of a fully expanded panel (padding + label + both stat columns),
        // so collapsing every section doesn't shrink the container.
        .frame(minWidth: 32 + Self.statLabelWidth + 2 * UsageStatColumns.columnWidth + UsageStatColumns.columnSpacing, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: antigravityExpanded) { _, value in
            UserDefaults.standard.set(value, forKey: "antigravityExpanded")
            announceToggle(expanded: value, sectionHeight: antigravityHeight)
        }
        .onChange(of: openCodeExpanded) { _, value in
            UserDefaults.standard.set(value, forKey: "openCodeExpanded")
            announceToggle(expanded: value, sectionHeight: openCodeHeight)
        }
        .onChange(of: claudeExpanded) { _, value in
            UserDefaults.standard.set(value, forKey: "claudeExpanded")
            announceToggle(expanded: value, sectionHeight: claudeHeight)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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
}
