import Foundation
import MLXLMCommon
import Tokenizers

struct ToolRegistry {

    static func allSchemas(braveAPIKeyAvailable: Bool) -> [ToolSpec] {
        var schemas: [ToolSpec] = [
            tipsSchema,
            productSearchSchema,
            urlFetchSchema,
        ]
        if braveAPIKeyAvailable {
            schemas.insert(webSearchSchema, at: 0)
        }
        return schemas
    }

    static func dispatch(
        toolCall: ToolCall,
        braveAPIKey: String?
    ) async -> (name: String, result: String, searchResults: [SearchResult]?) {
        let name = toolCall.function.name
        var args: [String: String] = [:]
        for (k, v) in toolCall.function.arguments {
            args[k] = v.stringValue ?? "\(v)"
        }
        return await dispatchByName(name: name, arguments: args, braveAPIKey: braveAPIKey)
    }

    static func dispatchByName(
        name: String,
        arguments: [String: String],
        braveAPIKey: String?
    ) async -> (name: String, result: String, searchResults: [SearchResult]?) {
        switch name {
        case "web_search":
            let query = arguments["query"] ?? ""
            guard let key = braveAPIKey, !key.isEmpty else {
                return (name, "Error: Brave Search API key not configured", nil)
            }
            let response = await BraveSearchService.searchWithResults(query: query, apiKey: key)
            return (name, response.text, response.results.isEmpty ? nil : response.results)

        case "product_search":
            let query = arguments["query"] ?? ""
            do {
                let products = try await Channel3Service.shared.search(query: query)
                if products.isEmpty {
                    return (name, "No products found for '\(query)'", nil)
                }
                var text = "Product results for '\(query)':\n\n"
                for (i, product) in products.prefix(10).enumerated() {
                    text += "\(i + 1). \(product.title)\n"
                    if let price = product.formattedPrice { text += "   Price: \(price)\n" }
                    if let desc = product.description, !desc.isEmpty { text += "   \(desc)\n" }
                    if let url = product.url, !url.isEmpty { text += "   URL: \(url)\n" }
                    text += "\n"
                }
                let searchResults = products.map { $0.toSearchResult() }
                return (name, text.trimmingCharacters(in: .whitespacesAndNewlines), searchResults)
            } catch {
                return (name, "Error searching products: \(error.localizedDescription)", nil)
            }

        case "url_fetch":
            let url = arguments["url"] ?? ""
            let result = await WebFetchService.fetch(urlString: url)
            return (name, result, nil)

        default:
            return (name, "Unknown tool: \(name)", nil)
        }
    }

    // MARK: - Schemas

    static let tipsSchema: ToolSpec = [
        "type": "function",
        "function": [
            "name": "tips",
            "description": "Show an interactive questionnaire UI to gather user preferences such as budget, brand, features, and use case. Use this INSTEAD of asking preference questions in text. Always call this tool when you need to ask the user about their shopping preferences.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The product or topic the user is asking about",
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
                "required": ["query"],
            ] as [String: any Sendable],
        ] as [String: any Sendable],
    ]

    static let webSearchSchema: ToolSpec = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Search the web for current information. Use this when the user asks about recent events, news, or anything that requires up-to-date information.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query",
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
                "required": ["query"],
            ] as [String: any Sendable],
        ] as [String: any Sendable],
    ]

    static let productSearchSchema: ToolSpec = [
        "type": "function",
        "function": [
            "name": "product_search",
            "description": "Search for products to buy. Use this when the user wants to find, compare, or purchase products, or asks about prices, shopping, or where to buy something.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The product search query",
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
                "required": ["query"],
            ] as [String: any Sendable],
        ] as [String: any Sendable],
    ]

    static let urlFetchSchema: ToolSpec = [
        "type": "function",
        "function": [
            "name": "url_fetch",
            "description": "Fetch and read the text content of a web page URL. Use this when the user provides a URL or when you need to read a specific web page.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The URL to fetch",
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
                "required": ["url"],
            ] as [String: any Sendable],
        ] as [String: any Sendable],
    ]
}

// MARK: - JSONValue helpers

extension JSONValue {
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
}
