import SwiftUI

/// Two-column masonry.
///
/// The reason this is not a `LazyVGrid` with `.adaptive` columns: a grid aligns
/// its rows, so a short card beside a tall one leaves a hole, and the covers
/// stop being flush. A waterfall has no rows — each column is its own stack and
/// the next card goes wherever there is least ink. That means the layout has to
/// know how tall a card WILL be before it places it, which is why the caller
/// supplies an estimator rather than the view measuring itself: measuring after
/// the fact would move cards between columns mid-scroll.
struct Waterfall<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    var columns: Int = 2
    var spacing: CGFloat = NV.gutter
    /// The grid applies its own horizontal inset rather than being wrapped in
    /// one by the caller. It has to know the true available width to size a
    /// column, and padding applied outside is invisible to it — the columns
    /// then come out one inset too wide and the right one runs off screen.
    var inset: CGFloat = 0
    var estimatedHeight: (Item, CGFloat) -> CGFloat
    @ViewBuilder var content: (Item, CGFloat) -> Content

    @State private var width: CGFloat = NV.screenWidth

    private var columnCount: Int {
        columns > 0 ? columns : NV.feedColumns(for: width)
    }

    private var columnWidth: CGFloat {
        let count = CGFloat(columnCount)
        let usable = width - inset * 2 - spacing * (count - 1)
        return max(1, (usable / count).rounded(.down))
    }

    /// Greedy shortest-column packing, in feed order. Anything cleverer —
    /// balancing the tails, say — reorders the feed, and the feed's order IS
    /// the ranking. It is not ours to rearrange for a tidier bottom edge.
    private var buckets: [[Item]] {
        let count = columnCount
        var out = Array(repeating: [Item](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        let w = columnWidth
        for item in items {
            var shortest = 0
            for c in 1..<count where heights[c] < heights[shortest] - 0.5 { shortest = c }
            out[shortest].append(item)
            heights[shortest] += estimatedHeight(item, w) + spacing
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            // Measured on a probe pinned to the SCROLL CONTAINER, not on the
            // columns. The columns are sized from this number, so measuring
            // them feeds the result back into its own input: one card that
            // reports itself wider than its column — a remote cover does,
            // because `scaledToFill` carries the image's own pixel size —
            // widens the grid permanently and pushes both edges off screen.
            Color.clear
                .frame(height: 0)
                .containerRelativeFrame(.horizontal)
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: WaterfallWidth.self, value: g.size.width)
                    }
                }

            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: spacing) {
                        ForEach(column) { item in
                            content(item, columnWidth)
                                // The column's width is the contract. Without
                                // it an oversized card grows the whole row.
                                .frame(width: columnWidth)
                        }
                    }
                    .frame(width: columnWidth)
                }
            }
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onPreferenceChange(WaterfallWidth.self) { w in
            if w > 0, abs(w - width) > 0.5 { width = w }
        }
    }
}

private struct WaterfallWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How many lines a title will take at a given width. `boundingRect` rather
/// than characters-per-line arithmetic: a title mixing 中文, latin and digits
/// ("无 SSN F-1 签证被批准了 6000usd 额度") has no single character width, and
/// guessing it wrong by one line is a visible step in the column.
func nv_lineCount(_ text: String, width: CGFloat, font: UIFont, limit: Int = 2) -> Int {
    guard width > 0, !text.isEmpty else { return 0 }
    let box = (text as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font],
        context: nil
    )
    return min(limit, max(1, Int((box.height / font.lineHeight).rounded(.up))))
}
