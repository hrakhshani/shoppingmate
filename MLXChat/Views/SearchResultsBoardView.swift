import SwiftUI

struct SearchResultsBoardView: View {
    let results: [SearchResult]
    var onSelect: ((SearchResult) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(results) { result in
                    SearchResultCard(result: result, onSelect: onSelect)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .clipped()
    }
}

private struct SearchResultCard: View {
    let result: SearchResult
    var onSelect: ((SearchResult) -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView
                .frame(height: 100)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                if let siteName = result.siteName, !siteName.isEmpty {
                    Text(siteName.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.marmaladeAmber)
                        .lineLimit(1)
                }

                Text(result.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.marmaladeCream)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !result.description.isEmpty {
                    Text(result.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.marmaladeMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let price = result.price, !price.isEmpty {
                    Text(price)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.marmaladeMint)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                    Text(hostName(from: result.url))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.marmaladeMuted.opacity(0.7))
                .padding(.top, 4)
            }
            .padding(9)
        }
        .frame(width: 158, alignment: .topLeading)
        .background(Color.marmaladeBg2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.marmaladeAmber.opacity(0.15), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let onSelect {
                onSelect(result)
            } else if let url = URL(string: result.url) {
                openURL(url)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbURL = result.thumbnailURL, let url = URL(string: thumbURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.marmaladeBg3)
            .overlay(
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(Color.marmaladeMuted.opacity(0.4))
            )
    }

    private func hostName(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}
