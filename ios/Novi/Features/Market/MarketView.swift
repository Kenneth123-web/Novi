import SwiftUI

/// 市集. Same waterfall as the feed, different card — which is the point of
/// having the waterfall be generic. A shop grid that aligned its rows would
/// read as a catalogue; keeping the ragged column is what keeps it feeling
/// like the same app one tab over.
struct MarketView: View {
    @State private var category = 0
    /// English catalog keys; translated at the point of display.
    private let categories = ["For You", "Outfits", "Home & Living", "Coffee", "Tech", "Beauty", "Handmade", "Outdoors"]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            chips
            ScrollView {
                Waterfall(
                    items: Fixtures.products,
                    estimatedHeight: { p, w in ProductCard.height(p, width: w) }
                ) { p, w in
                    ProductCard(product: p, width: w)
                }
                .padding(.horizontal, NV.gutter)
                .padding(.top, NV.gutter)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .background(NV.page)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NV.inkFaint)
                Text("Search for what you want")
                    .font(.system(size: 13.5))
                    .foregroundStyle(NV.inkGhost)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(NV.fill, in: Capsule())

            Image(systemName: "bag")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(NV.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(NV.surface)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(Array(categories.enumerated()), id: \.offset) { i, name in
                    VStack(spacing: 4) {
                        Text(name.localized)
                            .font(.system(size: i == category ? 15.5 : 14.5,
                                          weight: i == category ? .semibold : .regular))
                            .foregroundStyle(i == category ? NV.ink : NV.inkFaint)
                        Capsule()
                            .fill(i == category ? NV.red : .clear)
                            .frame(width: 16, height: 3)
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { category = i }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .frame(height: 40)
        .background(NV.surface)
        .hairline()
    }
}

struct ProductCard: View {
    let product: Fixtures.Product
    let width: CGFloat

    private static let titleFont = UIFont.systemFont(ofSize: 14, weight: .regular)

    static func height(_ p: Fixtures.Product, width: CGFloat) -> CGFloat {
        let cover = (width / max(0.4, p.ratio)).rounded()
        let lines = CGFloat(nv_lineCount(p.title, width: width - 20, font: titleFont))
        return cover + 9 + lines * titleFont.lineHeight.rounded(.up) + (lines - 1) * 3 + 8 + 20 + 6 + 15 + 9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverArt(seed: "product-" + product.id)
                .frame(width: width, height: (width / max(0.4, product.ratio)).rounded())
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let tag = product.tag {
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(NV.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                            .padding(7)
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(product.title)
                    .font(Font(ProductCard.titleFont))
                    .foregroundStyle(NV.ink)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("¥").font(.system(size: 12, weight: .semibold))
                    Text("\(product.price)").font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(product.sold)
                        .font(.system(size: 11))
                        .foregroundStyle(NV.inkGhost)
                }
                .foregroundStyle(NV.red)
                .padding(.top, 8)
                .frame(height: 20)

                Text(product.shop)
                    .font(.system(size: 11))
                    .foregroundStyle(NV.inkFaint)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .frame(height: 15)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(width: width, alignment: .leading)
        .background(NV.surface)
        .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
    }
}
