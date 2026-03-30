import Foundation
import UIKit

enum ChatRole: Sendable {
    case user
    case assistant
    case system
    case tool
}

struct ProductQuestionnaire: Sendable {
    let originalQuery: String
    var priceRange: ClosedRange<Double> = 0...5000
    var brand: String = ""
    var condition: String = "Any"
    var sortBy: String = "Relevance"
    var isSubmitted: Bool = false

    static let conditionOptions = ["Any", "New", "Used", "Refurbished"]
    static let sortOptions = ["Relevance", "Price: Low to High", "Price: High to Low", "Top Rated"]
}

struct TipsQuestionnaire: Sendable {
    let originalQuery: String
    var budgetMin: Double = 0
    var budgetMax: Double = 5000
    var brand: String = ""
    var condition: String = "Any"
    var sortBy: String = "Relevance"
    var priorities: [String: Bool] = [:]
    var useCase: String = "Personal Use"
    var isSubmitted: Bool = false

    static let priorityOptions = [
        "Quality", "Value for Money", "Durability", "Brand Reputation",
        "Good Reviews", "Fast Delivery", "Warranty", "Eco-friendly"
    ]
    static let useCaseOptions = [
        "Personal Use", "Gift", "Business", "Education", "Other"
    ]
    static let conditionOptions = ["Any", "New", "Used", "Refurbished"]
    static let sortOptions = ["Relevance", "Price: Low to High", "Price: High to Low", "Top Rated"]

    var selectedPriorities: [String] {
        Self.priorityOptions.filter { priorities[$0] == true }
    }

    var budgetSummary: String? {
        guard budgetMin > 0 || budgetMax < 5000 else { return nil }
        return "$\(Int(budgetMin)) - $\(Int(budgetMax))"
    }

    func toToolResult() -> String {
        var parts: [String] = []
        parts.append("User preferences for: \(originalQuery)")
        if budgetMin > 0 || budgetMax < 5000 {
            parts.append("Budget: $\(Int(budgetMin)) - $\(Int(budgetMax))")
        }
        if !brand.isEmpty {
            parts.append("Preferred brand: \(brand)")
        }
        if !selectedPriorities.isEmpty {
            parts.append("Priorities: \(selectedPriorities.joined(separator: ", "))")
        }
        if useCase != "Personal Use" {
            parts.append("Use case: \(useCase)")
        }
        if condition != "Any" {
            parts.append("Condition: \(condition)")
        }
        if sortBy != "Relevance" {
            parts.append("Sort by: \(sortBy)")
        }
        return parts.joined(separator: "\n")
    }
}

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let description: String
    let url: String
    let thumbnailURL: String?
    let siteName: String?
    let price: String?
}

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: ChatRole
    var text: String
    var displayText: String?
    var thinkingText: String?
    var image: UIImage?
    var metrics: GenerationMetrics?
    let toolName: String?
    var searchResults: [SearchResult]?
    var toolCallTokens: String?
    var questionnaire: ProductQuestionnaire?
    var tipsQuestionnaire: TipsQuestionnaire?
    var isHidden: Bool
    let timestamp = Date()

    init(
        role: ChatRole,
        text: String,
        displayText: String? = nil,
        thinkingText: String? = nil,
        image: UIImage? = nil,
        metrics: GenerationMetrics? = nil,
        toolName: String? = nil,
        searchResults: [SearchResult]? = nil,
        toolCallTokens: String? = nil,
        questionnaire: ProductQuestionnaire? = nil,
        tipsQuestionnaire: TipsQuestionnaire? = nil,
        isHidden: Bool = false
    ) {
        self.role = role
        self.text = text
        self.displayText = displayText
        self.thinkingText = thinkingText
        self.image = image
        self.metrics = metrics
        self.toolName = toolName
        self.searchResults = searchResults
        self.toolCallTokens = toolCallTokens
        self.questionnaire = questionnaire
        self.tipsQuestionnaire = tipsQuestionnaire
        self.isHidden = isHidden
    }
}
