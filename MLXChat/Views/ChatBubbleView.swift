import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    var onProductSelect: ((SearchResult) -> Void)? = nil
    var onQuestionnaireSubmit: ((ProductQuestionnaire) -> Void)? = nil
    var onTipsSubmit: ((TipsQuestionnaire) -> Void)? = nil
    @State private var showCopied = false
    @State private var showThinking = false
    @State private var showToolTokens = false

    var body: some View {
        if message.tipsQuestionnaire != nil {
            tipsQuestionnaireBubble
        } else if message.questionnaire != nil {
            questionnaireBubble
        } else if message.role == .tool {
            toolBubble
        } else {
            chatBubble
        }
    }

    private var chatBubble: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
            HStack {
                if message.role == .user { Spacer(minLength: 60) }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    // Copy button for assistant messages
                    if message.role == .assistant && !visibleText.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                UIPasteboard.general.string = visibleText
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopied = false
                                }
                            } label: {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(Color.marmaladeMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let image = message.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Collapsible thinking section
                    if let thinking = message.thinkingText, !thinking.isEmpty {
                        thinkingSection(thinking)
                    }

                    if !(visibleText.isEmpty) {
                        messageTextView
                    }
                }
                .padding(10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            message.role == .user
                                ? Color.clear
                                : Color.marmaladeAmber.opacity(0.18),
                            lineWidth: 1
                        )
                )

                if message.role == .assistant { Spacer(minLength: 60) }
            }

            // Stats below the bubble
            if message.role == .assistant, let metrics = message.metrics, metrics.tokensPerSecond > 0 {
                HStack(spacing: 8) {
                    Text(String(format: "%.1f tok/s model", metrics.tokensPerSecond))
                    Text("\(metrics.generationTokenCount) tokens")
                    Text(String(format: "%.1fs gen", metrics.generateTimeSeconds))
                    if metrics.totalTimeSeconds > metrics.generateTimeSeconds + 0.2 {
                        Text(String(format: "%.1fs total", metrics.totalTimeSeconds))
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.marmaladeMuted.opacity(0.7))
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            LinearGradient(
                colors: [.marmaladeAmber, Color(red: 224/255, green: 145/255, blue: 18/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.marmaladeBg2.opacity(0.85)
        }
    }

    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .font(.caption)
                    .foregroundStyle(Color.marmaladeAmber)

                Text(toolCompletedLabel)
                    .font(.caption)
                    .foregroundStyle(Color.marmaladeMuted)

                Spacer()
            }
            .padding(.horizontal)

            if let results = message.searchResults, !results.isEmpty {
                SearchResultsBoardView(results: results, onSelect: onProductSelect)
                    .frame(height: 220)
                    .clipped()
            } else if !message.text.isEmpty {
                Text(message.text)
                    .font(.caption2)
                    .foregroundStyle(Color.marmaladeMuted)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }

            // Collapsible debug view for raw tool call tokens
            if let tokens = message.toolCallTokens, !tokens.isEmpty {
                toolCallTokensSection(tokens)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var questionnaireBubble: some View {
        if let q = message.questionnaire {
            if q.isSubmitted {
                // Show a compact summary after submission
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.marmaladeMint)
                        Text("Filters applied")
                            .font(.caption)
                            .foregroundStyle(Color.marmaladeMuted)
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.caption2)
                            .foregroundStyle(Color.marmaladeMuted.opacity(0.8))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            } else {
                ProductQuestionnaireView(
                    originalQuery: q.originalQuery,
                    onSubmit: { filled in
                        onQuestionnaireSubmit?(filled)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var tipsQuestionnaireBubble: some View {
        if let q = message.tipsQuestionnaire {
            if q.isSubmitted {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.marmaladeMint)
                        Text("Preferences submitted")
                            .font(.caption)
                            .foregroundStyle(Color.marmaladeMuted)
                    }
                    tipsSummaryView(q)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            } else {
                TipsQuestionnaireView(
                    originalQuery: q.originalQuery,
                    onSubmit: { filled in
                        onTipsSubmit?(filled)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func tipsSummaryView(_ questionnaire: TipsQuestionnaire) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(questionnaire.originalQuery)
                .font(.caption)
                .foregroundStyle(Color.marmaladeCream)

            if let budget = questionnaire.budgetSummary {
                summaryRow(label: "Budget", value: budget)
            }

            if !questionnaire.brand.isEmpty {
                summaryRow(label: "Brand", value: questionnaire.brand)
            }

            if !questionnaire.selectedPriorities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Priorities")
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeMuted)
                    flexibleTagRow(questionnaire.selectedPriorities)
                }
            }

            if questionnaire.useCase != "Personal Use" {
                summaryRow(label: "Use Case", value: questionnaire.useCase)
            }

            if questionnaire.condition != "Any" {
                summaryRow(label: "Condition", value: questionnaire.condition)
            }

            if questionnaire.sortBy != "Relevance" {
                summaryRow(label: "Sort", value: questionnaire.sortBy)
            }

            if questionnaire.budgetSummary == nil,
               questionnaire.brand.isEmpty,
               questionnaire.selectedPriorities.isEmpty,
               questionnaire.useCase == "Personal Use",
               questionnaire.condition == "Any",
               questionnaire.sortBy == "Relevance" {
                Text("Using default preferences.")
                    .font(.caption2)
                    .foregroundStyle(Color.marmaladeMuted.opacity(0.8))
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.marmaladeMuted)
            Text(value)
                .font(.caption2)
                .foregroundStyle(Color.marmaladeCream)
        }
    }

    private func flexibleTagRow(_ values: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption2)
                        .foregroundStyle(Color.marmaladeAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.marmaladeAmber.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.marmaladeAmber.opacity(0.22), lineWidth: 1)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showThinking.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Thinking")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.marmaladeMuted)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(.caption2)
                    .foregroundStyle(Color.marmaladeMuted.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.marmaladeBg.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func toolCallTokensSection(_ tokens: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showToolTokens.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showToolTokens ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "curlybraces")
                        .font(.caption2)
                    Text("Tool Call Tokens")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.marmaladeMuted.opacity(0.7))
            }
            .buttonStyle(.plain)

            if showToolTokens {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(tokens)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.marmaladeMuted.opacity(0.8))
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.marmaladeBg.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.marmaladeMuted.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    private var visibleText: String {
        message.displayText ?? message.text
    }

    @ViewBuilder
    private var messageTextView: some View {
        if message.role == .assistant {
            markdownContentView(visibleText)
                .foregroundStyle(Color.marmaladeCream)
        } else {
            Text(visibleText)
                .font(.footnote)
                .foregroundStyle(message.role == .user ? Color.marmaladeBg : Color.marmaladeCream)
                .textSelection(.enabled)
        }
    }

    // MARK: - Markdown with table support

    @ViewBuilder
    private func markdownContentView(_ text: String) -> some View {
        let segments = Self.parseMarkdownSegments(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(Self.renderAttributedMarkdown(content))
                        .font(.footnote)
                        .textSelection(.enabled)
                case .table(let headers, let alignments, let rows):
                    markdownTableView(headers: headers, alignments: alignments, rows: rows)
                }
            }
        }
    }

    @ViewBuilder
    private func markdownTableView(headers: [String], alignments: [HorizontalAlignment], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                        Text(Self.renderInlineMarkdown(header))
                            .font(.caption.bold())
                            .frame(minWidth: 60, alignment: alignments.indices.contains(i) ? alignmentToFrameAlignment(alignments[i]) : .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color.marmaladeAmber.opacity(0.12))

                // Separator
                Rectangle()
                    .fill(Color.marmaladeMuted.opacity(0.3))
                    .frame(height: 1)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                            Text(Self.renderInlineMarkdown(cell))
                                .font(.caption2)
                                .frame(minWidth: 60, alignment: alignments.indices.contains(i) ? alignmentToFrameAlignment(alignments[i]) : .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : Color.marmaladeMuted.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.marmaladeMuted.opacity(0.2), lineWidth: 1)
            )
        }
        .textSelection(.enabled)
    }

    private func alignmentToFrameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    // MARK: - Markdown parsing helpers

    private enum MarkdownSegment {
        case text(String)
        case table(headers: [String], alignments: [HorizontalAlignment], rows: [[String]])
    }

    private static func parseMarkdownSegments(_ text: String) -> [MarkdownSegment] {
        let lines = text.components(separatedBy: "\n")
        var segments: [MarkdownSegment] = []
        var currentText: [String] = []
        var i = 0

        while i < lines.count {
            // Check if this line starts a markdown table (must have | and next line is separator)
            if i + 1 < lines.count,
               isTableRow(lines[i]),
               isTableSeparator(lines[i + 1]) {

                // Flush accumulated text
                if !currentText.isEmpty {
                    let joined = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty {
                        segments.append(.text(joined))
                    }
                    currentText = []
                }

                // Parse headers
                let headers = parseTableCells(lines[i])
                let alignments = parseAlignments(lines[i + 1])
                var rows: [[String]] = []
                i += 2

                // Parse data rows
                while i < lines.count, isTableRow(lines[i]) {
                    rows.append(parseTableCells(lines[i]))
                    i += 1
                }

                segments.append(.table(headers: headers, alignments: alignments, rows: rows))
            } else {
                currentText.append(lines[i])
                i += 1
            }
        }

        // Flush remaining text
        if !currentText.isEmpty {
            let joined = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                segments.append(.text(joined))
            }
        }

        return segments
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " })
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") && trimmed.contains("-") else { return false }
        // Should only contain |, -, :, and spaces
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseAlignments(_ line: String) -> [HorizontalAlignment] {
        return parseTableCells(line).map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(":") && t.hasSuffix(":") { return .center }
            if t.hasSuffix(":") { return .trailing }
            return .leading
        }
    }

    private static func renderAttributedMarkdown(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        if let full = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            return full
        }
        if let inline = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return inline
        }
        return AttributedString(text)
    }

    private static func renderInlineMarkdown(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        if let result = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return result
        }
        return AttributedString(text)
    }

    private var toolCompletedLabel: String {
        switch message.toolName {
        case "web_search": return "Searched the web"
        case "product_search": return "Searched for products"
        case "url_fetch": return "Fetched URL"
        case "tips": return "Preferences gathered"
        default: return "Used \(message.toolName ?? "tool")"
        }
    }

    private var toolIcon: String {
        switch message.toolName {
        case "web_search": return "magnifyingglass"
        case "product_search": return "cart"
        case "url_fetch": return "globe"
        case "tips": return "questionmark.bubble"
        default: return "wrench"
        }
    }
}
