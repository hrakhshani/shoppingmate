import SwiftUI

struct ProductQuestionnaireView: View {
    let originalQuery: String
    var onSubmit: (ProductQuestionnaire) -> Void

    @State private var minPrice: Double = 0
    @State private var maxPrice: Double = 5000
    @State private var brand: String = ""
    @State private var selectedCondition: String = "Any"
    @State private var selectedSort: String = "Relevance"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Color.marmaladeAmber)
                Text("Help us find the best match")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.marmaladeCream)
            }

            Text("Answer a few quick questions to refine your search for: **\(originalQuery)**")
                .font(.caption)
                .foregroundStyle(Color.marmaladeMuted)

            Divider()
                .background(Color.marmaladeAmber.opacity(0.2))

            // Price range
            VStack(alignment: .leading, spacing: 6) {
                Text("Price Range")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.marmaladeTan)

                HStack {
                    Text("$\(Int(minPrice))")
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeMint)
                        .frame(width: 50, alignment: .leading)

                    VStack(spacing: 4) {
                        Slider(value: $maxPrice, in: minPrice...10000, step: 50)
                            .tint(Color.marmaladeAmber)
                        Slider(value: $minPrice, in: 0...maxPrice, step: 50)
                            .tint(Color.marmaladeAmber.opacity(0.5))
                    }

                    Text("$\(Int(maxPrice))")
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeMint)
                        .frame(width: 55, alignment: .trailing)
                }
            }

            // Brand
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferred Brand (optional)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.marmaladeTan)

                TextField("e.g. Apple, Samsung, Nike...", text: $brand)
                    .font(.caption)
                    .foregroundStyle(Color.marmaladeCream)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.marmaladeAmber.opacity(0.2), lineWidth: 1)
                    )
            }

            // Condition & Sort in a row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Condition")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.marmaladeTan)

                    Menu {
                        ForEach(ProductQuestionnaire.conditionOptions, id: \.self) { option in
                            Button(option) { selectedCondition = option }
                        }
                    } label: {
                        HStack {
                            Text(selectedCondition)
                                .font(.caption)
                                .foregroundStyle(Color.marmaladeCream)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(Color.marmaladeMuted)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.marmaladeAmber.opacity(0.2), lineWidth: 1)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sort By")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.marmaladeTan)

                    Menu {
                        ForEach(ProductQuestionnaire.sortOptions, id: \.self) { option in
                            Button(option) { selectedSort = option }
                        }
                    } label: {
                        HStack {
                            Text(selectedSort)
                                .font(.caption)
                                .foregroundStyle(Color.marmaladeCream)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(Color.marmaladeMuted)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.marmaladeAmber.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }

            // Submit and Skip buttons
            HStack(spacing: 10) {
                Button {
                    submitQuestionnaire()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                        Text("Search with Filters")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.marmaladeBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.marmaladeAmber, Color(red: 224/255, green: 145/255, blue: 18/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    // Skip: submit with defaults (essentially no filters)
                    var q = ProductQuestionnaire(originalQuery: originalQuery)
                    q.isSubmitted = true
                    onSubmit(q)
                } label: {
                    Text("Skip")
                        .font(.caption)
                        .foregroundStyle(Color.marmaladeMuted)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.marmaladeMuted.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.marmaladeBg2.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.marmaladeAmber.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private func submitQuestionnaire() {
        var q = ProductQuestionnaire(originalQuery: originalQuery)
        q.priceRange = minPrice...maxPrice
        q.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        q.condition = selectedCondition
        q.sortBy = selectedSort
        q.isSubmitted = true
        onSubmit(q)
    }
}
