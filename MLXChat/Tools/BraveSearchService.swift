import Foundation

struct BraveSearchResponse: Sendable {
    let text: String
    let results: [SearchResult]
}

enum BraveSearchService {

    static func search(query: String, apiKey: String, count: Int = 5) async -> String {
        await searchWithResults(query: query, apiKey: apiKey, count: count).text
    }

    static func searchWithResults(query: String, apiKey: String, count: Int = 8) async -> BraveSearchResponse {
        guard !query.isEmpty else {
            return BraveSearchResponse(text: "Error: Empty search query", results: [])
        }

        guard var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search") else {
            return BraveSearchResponse(text: "Error: Invalid URL", results: [])
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count)),
        ]

        guard let url = components.url else {
            return BraveSearchResponse(text: "Error: Could not build search URL", results: [])
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return BraveSearchResponse(text: "Error: Invalid response", results: [])
            }
            guard httpResponse.statusCode == 200 else {
                return BraveSearchResponse(
                    text: "Error: Search API returned status \(httpResponse.statusCode)", results: [])
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // Parse web results
            var structured: [SearchResult] = []
            var textOutput = "Search results for '\(query)':\n\n"

            if let webResults = json?["web"] as? [String: Any],
               let rawResults = webResults["results"] as? [[String: Any]] {
                for (i, item) in rawResults.prefix(count).enumerated() {
                    let title = item["title"] as? String ?? "No title"
                    let description = item["description"] as? String ?? ""
                    let resultUrl = item["url"] as? String ?? ""

                    let thumbnail = (item["thumbnail"] as? [String: Any])?["src"] as? String
                    let profile = item["profile"] as? [String: Any]
                    let siteName = profile?["name"] as? String

                    // Shopping price if present
                    let price = (item["price"] as? [String: Any])?["price"] as? String

                    structured.append(SearchResult(
                        title: title,
                        description: description,
                        url: resultUrl,
                        thumbnailURL: thumbnail,
                        siteName: siteName,
                        price: price
                    ))

                    textOutput += "\(i + 1). \(title)\n"
                    if !description.isEmpty { textOutput += "   \(description)\n" }
                    if !resultUrl.isEmpty { textOutput += "   URL: \(resultUrl)\n" }
                    textOutput += "\n"
                }
            }

            if structured.isEmpty {
                return BraveSearchResponse(text: "No results found for '\(query)'", results: [])
            }

            return BraveSearchResponse(
                text: textOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                results: structured
            )
        } catch {
            return BraveSearchResponse(text: "Error: \(error.localizedDescription)", results: [])
        }
    }
}
