import SwiftUI

/// A provider's header and its collapsible rows.
struct ProviderSectionView: View {
    let section: UsageSection
    let now: Date
    @Binding var isExpanded: Bool
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: section.title, tint: section.tint, isExpanded: $isExpanded)
                .panelInset()
                .padding(.top, 10)
                .padding(.bottom, isExpanded ? 12 : 10)

            CollapsibleSection(isExpanded: isExpanded, onHeightChange: onHeightChange) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        LabeledRow(row: row, now: now)
                            .panelInset()
                            .padding(.bottom, index == section.rows.count - 1 ? 10 : 8)
                    }
                }
            }
        }
    }
}
