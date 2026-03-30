import SwiftUI

struct TipsQuestionnaireView: View {
    private enum Step: Int, CaseIterable {
        case budget
        case priorities
        case useCase
        case brand
        case condition
        case sort

        var title: String {
            switch self {
            case .budget: return "Budget"
            case .priorities: return "Priorities"
            case .useCase: return "Use Case"
            case .brand: return "Brand"
            case .condition: return "Condition"
            case .sort: return "Sort"
            }
        }

        var prompt: String {
            switch self {
            case .budget: return "What budget range should we stay within?"
            case .priorities: return "What matters most for this purchase?"
            case .useCase: return "What is this purchase for?"
            case .brand: return "Do you have a preferred brand?"
            case .condition: return "Which condition should we look for?"
            case .sort: return "How should the results be ordered?"
            }
        }

        var icon: String {
            switch self {
            case .budget: return "dollarsign.circle"
            case .priorities: return "checklist"
            case .useCase: return "target"
            case .brand: return "tag"
            case .condition: return "shippingbox"
            case .sort: return "arrow.up.arrow.down"
            }
        }
    }

    let originalQuery: String
    var onSubmit: (TipsQuestionnaire) -> Void

    @State private var minPrice: Double = 0
    @State private var maxPrice: Double = 5000
    @State private var brand: String = ""
    @State private var selectedCondition: String = "Any"
    @State private var selectedSort: String = "Relevance"
    @State private var selectedPriorities: [String: Bool] = {
        var dict: [String: Bool] = [:]
        for option in TipsQuestionnaire.priorityOptions { dict[option] = false }
        return dict
    }()
    @State private var selectedUseCase: String = "Personal Use"
    @State private var stepIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.marmaladeAmber)
                Text("Questionnaire")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.marmaladeCream)
                Spacer()
                Text("Step \(stepIndex + 1) of \(Step.allCases.count)")
                    .font(.caption2)
                    .foregroundStyle(Color.marmaladeMuted)
            }

            Text("Help us find the best match for **\(originalQuery)**")
                .font(.caption)
                .foregroundStyle(Color.marmaladeMuted)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.22))
                    Capsule()
                        .fill(Color.marmaladeAmber.opacity(0.85))
                        .frame(width: max(28, proxy.size.width * progress))
                }
            }
            .frame(height: 6)

            Divider()
                .background(Color.marmaladeAmber.opacity(0.2))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: currentStep.icon)
                        .font(.caption)
                        .foregroundStyle(Color.marmaladeAmber)
                    Text(currentStep.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.marmaladeTan)
                }

                Text(currentStep.prompt)
                    .font(.caption)
                    .foregroundStyle(Color.marmaladeMuted)
            }

            stepContent

            HStack(spacing: 10) {
                if stepIndex > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            stepIndex -= 1
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Back")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.marmaladeMuted)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.marmaladeMuted.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Spacer()

                Button {
                    submitDefaults()
                } label: {
                    Text("Skip")
                        .font(.caption)
                        .foregroundStyle(Color.marmaladeMuted)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.marmaladeMuted.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    advanceOrSubmit()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isLastStep ? "paperplane.fill" : "arrow.right")
                            .font(.caption)
                        Text(isLastStep ? "Submit Preferences" : "Next")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.marmaladeBg)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            colors: [.marmaladeAmber, Color(red: 224 / 255, green: 145 / 255, blue: 18 / 255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .budget:
            budgetStep
        case .priorities:
            prioritiesStep
        case .useCase:
            useCaseStep
        case .brand:
            brandStep
        case .condition:
            conditionStep
        case .sort:
            sortStep
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                budgetValuePill("$\(Int(minPrice)) min")
                Spacer()
                budgetValuePill("$\(Int(maxPrice)) max")
            }

            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maximum")
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeMuted)
                    Slider(value: $maxPrice, in: minPrice...10000, step: 50)
                        .tint(Color.marmaladeAmber)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum")
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeMuted)
                    Slider(value: $minPrice, in: 0...maxPrice, step: 50)
                        .tint(Color.marmaladeAmber.opacity(0.55))
                }
            }
        }
    }

    private var prioritiesStep: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(TipsQuestionnaire.priorityOptions, id: \.self) { option in
                Button {
                    selectedPriorities[option]?.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedPriorities[option] == true
                              ? "checkmark.square.fill"
                              : "square")
                            .font(.caption2)
                        Text(option)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                    .foregroundStyle(
                        selectedPriorities[option] == true
                        ? Color.marmaladeAmber
                        : Color.marmaladeMuted
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(
                        selectedPriorities[option] == true
                        ? Color.marmaladeAmber.opacity(0.12)
                        : Color.black.opacity(0.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selectedPriorities[option] == true
                                ? Color.marmaladeAmber.opacity(0.4)
                                : Color.marmaladeAmber.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var useCaseStep: some View {
        optionList(
            options: TipsQuestionnaire.useCaseOptions,
            selected: selectedUseCase
        ) { option in
            selectedUseCase = option
        }
    }

    private var brandStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. Apple, Sony, Patagonia...", text: $brand)
                .font(.caption)
                .foregroundStyle(Color.marmaladeCream)
                .textInputAutocapitalization(.words)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.marmaladeAmber.opacity(0.2), lineWidth: 1)
                )

            Text("Leave this empty if brand does not matter.")
                .font(.caption2)
                .foregroundStyle(Color.marmaladeMuted)
        }
    }

    private var conditionStep: some View {
        optionList(
            options: TipsQuestionnaire.conditionOptions,
            selected: selectedCondition
        ) { option in
            selectedCondition = option
        }
    }

    private var sortStep: some View {
        optionList(
            options: TipsQuestionnaire.sortOptions,
            selected: selectedSort
        ) { option in
            selectedSort = option
        }
    }

    private func budgetValuePill(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(Color.marmaladeMint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.22))
            .clipShape(Capsule())
    }

    private func optionList(
        options: [String],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected == option ? "circle.inset.filled" : "circle")
                            .font(.caption2)
                        Text(option)
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(selected == option ? Color.marmaladeAmber : Color.marmaladeCream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(selected == option ? Color.marmaladeAmber.opacity(0.12) : Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selected == option ? Color.marmaladeAmber.opacity(0.4) : Color.marmaladeAmber.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentStep: Step {
        Step.allCases[stepIndex]
    }

    private var isLastStep: Bool {
        stepIndex == Step.allCases.count - 1
    }

    private var progress: CGFloat {
        CGFloat(stepIndex + 1) / CGFloat(Step.allCases.count)
    }

    private func advanceOrSubmit() {
        if isLastStep {
            submitQuestionnaire()
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            stepIndex += 1
        }
    }

    private func submitDefaults() {
        var q = TipsQuestionnaire(originalQuery: originalQuery)
        q.isSubmitted = true
        onSubmit(q)
    }

    private func submitQuestionnaire() {
        var q = TipsQuestionnaire(originalQuery: originalQuery)
        q.budgetMin = minPrice
        q.budgetMax = maxPrice
        q.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        q.condition = selectedCondition
        q.sortBy = selectedSort
        q.priorities = selectedPriorities
        q.useCase = selectedUseCase
        q.isSubmitted = true
        onSubmit(q)
    }
}
