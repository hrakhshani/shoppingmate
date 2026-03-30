import Foundation
import UIKit
import MLXLMCommon
import Tokenizers

/// Thread-safe holder for the tips tool async continuation.
final class TipsContinuationHolder: @unchecked Sendable {
    private var continuation: CheckedContinuation<String, Never>?
    private let lock = NSLock()

    func set(_ c: CheckedContinuation<String, Never>) {
        lock.lock()
        continuation = c
        lock.unlock()
    }

    func resume(with value: String) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

@MainActor
@Observable
final class ChatViewModel {
    private enum PendingTipsFlow {
        case toolCall
        case syntheticFollowUp
    }

    var messages: [ChatMessage] = []
    var isGenerating = false
    var error: String?
    var statusMessage: String?
    var thinkingEnabled = false
    private var streamingMessageIndex: Int?
    private var pendingToolMessageIndex: Int?
    var generationTask: Task<Void, Never>?
    private var productQuestionnaireShown = false
    var pendingQuestionnaireMessageIndex: Int?
    private var tipsContinuationHolder: TipsContinuationHolder?
    private var pendingTipsMessageIndex: Int?
    private var pendingTipsFlow: PendingTipsFlow?
    private var memoryWarningObserver: NSObjectProtocol?
    private var currentGenerationUsesVision = false

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }
    }

    /// The selected model spec (set by ModelPickerView).
    var selectedModel: ModelSpec? {
        didSet {
            if let spec = selectedModel {
                SettingsManager.shared.loadedModelId = spec.hfId
                SettingsManager.shared.loadedModelName = spec.displayName
            }
        }
    }

    private var engine: MLXEngine? { SettingsManager.shared.sharedEngine }

    var isThinkingModel: Bool {
        guard let model = selectedModel ?? resolvedModel else { return false }
        return model.isThinkingModel && model.supportsNoThink
    }

    /// Resolve current model from SettingsManager if no explicit selection.
    private var resolvedModel: ModelSpec? {
        guard let hfId = SettingsManager.shared.loadedModelId else { return nil }
        return ModelRegistry.find(hfId: hfId)
    }

    private var currentModel: ModelSpec? {
        selectedModel ?? resolvedModel
    }

    func sendMessage(text: String, image: UIImage?, displayUserMessage: Bool = true) async {
        guard let model = currentModel else {
            error = "No model selected — tap the model picker to choose one"
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil else { return }

        if image != nil && !model.supportsVision {
            error = "'\(model.displayName)' doesn't support images."
            return
        }

        let settings = SettingsManager.shared
        let maxEdge = CGFloat(settings.maxImageDimension)
        let quality = settings.jpegQuality
        let needsVision = image != nil

        // Resize and compress image
        let processedImage: UIImage? = image.flatMap { img in
            autoreleasepool {
                let resized = resizeImage(img, maxEdge: maxEdge)
                return compressImage(resized, quality: quality)
            }
        }

        if needsVision && processedImage == nil {
            error = "Failed to prepare the selected image for vision input."
            return
        }

        let userMessage = ChatMessage(
            role: .user,
            text: text,
            image: processedImage,
            isHidden: !displayUserMessage
        )
        messages.append(userMessage)

        if let preflightError = visionPreflightFailure(
            for: model,
            image: processedImage,
            settings: settings
        ) {
            error = preflightError
            statusMessage = nil
            return
        }

        isGenerating = true
        error = nil
        currentGenerationUsesVision = needsVision

        do {
            var engine = self.engine
            let hasBraveKey = !settings.braveAPIKey.isEmpty
            let preflightTool = Self.preflightToolCall(
                for: text,
                hasImage: image != nil,
                toolsEnabled: settings.toolsEnabled,
                braveAPIKeyAvailable: hasBraveKey
            )

            if engine == nil {
                statusMessage = "Loading \(model.displayName)..."
                let newEngine = MLXEngine(memoryLimitGB: settings.gpuMemoryLimitGB)
                _ = try await newEngine.loadModel(id: model.hfId, forVision: needsVision)
                settings.sharedEngine = newEngine
                engine = newEngine
            } else {
                let currentlyVLM = await engine!.loadedAsVLM
                if needsVision && !currentlyVLM {
                    // Currently loaded as LLM but need VLM for image — reload
                    statusMessage = "Loading vision model..."
                    _ = try await engine!.loadModel(id: model.hfId, forVision: true)
                } else if !needsVision && currentlyVLM {
                    // Currently loaded as VLM but no image — reload as LLM for speed + better tools
                    statusMessage = "Loading \(model.displayName)..."
                    _ = try await engine!.loadModel(id: model.hfId, forVision: false)
                }
            }

            guard let engine else {
                error = "Failed to load model"
                isGenerating = false
                return
            }

            if needsVision {
                await engine.clearCache()
            }

            statusMessage = "Generating..."

            var chatMessages: [Chat.Message] = []
            let toolsActive = Self.shouldEnableTools(
                for: text,
                hasImage: image != nil,
                toolsEnabled: settings.toolsEnabled
            )
            let useDirectToolPrefetch = preflightTool != nil
            let currentInfoPrompt = Self.requiresCurrentInfo(text)

            // Hardcoded shopping assistant system prompt with variable substitution
            let systemPromptTemplate = """
            You are a friendly shopping assistant. Your primary goal is to help users find the products they need, compare options, and make informed purchasing decisions. Today is {today} and the time is {time} in the {timezone} timezone. Your rough location is {location} and your coordinates are {coordinates}. Use British English spelling. Do not use this information unless relevant to the user's question.

            You have the following tools available:
            - tips: Use this to gather user preferences through an interactive UI. When you need to ask about budget, brand, features, or use case, ALWAYS call the tips tool instead of asking in text. The tips tool shows sliders, checkboxes, and radio buttons for the user to fill in.
            - product_search: Use this to search for products when the user wants to buy, shop, or compare items. Great for finding deals, checking prices, and discovering options.
            - web_search: Use this to look up current information such as latest news, reviews, stock prices, or any real-time data the user needs.
            - url_fetch: Use this to fetch and read the contents of a specific URL the user shares with you.

            Tips: When you need to ask clarifying questions about budget, preferred brands, specific features, or use case, you MUST call the tips tool. Do NOT ask these questions in text. The tips tool will show an interactive questionnaire UI to the user and return their answers. After receiving the tips result, use those preferences to search for products or give recommendations.
            """
            let systemPromptText = settings.substituteVariables(in: systemPromptTemplate)
            var systemText = systemPromptText
            if model.supportsNoThink {
                if thinkingEnabled {
                    systemText += "\nThinking mode is enabled for this turn."
                } else {
                    systemText += "\nThinking mode is disabled for this turn. Reply with only the final answer. Do not output hidden reasoning, self-corrections, or deliberation. For simple questions, answer in one short sentence."
                }
            }
            if toolsActive && !useDirectToolPrefetch {
                systemText += "\nYou have tools available but only use them when needed. For simple conversation, respond directly. Use product_search for shopping/buying queries and web_search for general current-information queries."
                systemText += "\nTo call a tool, reply with ONLY this exact XML format and no trailing text:"
                systemText += "\n<tool_call>\n<function=tool_name>\n<parameter=param_name>value</parameter>\n</function>\n</tool_call>"
                if currentInfoPrompt, hasBraveKey {
                    systemText += "\nThis user is asking for current or recent information. You must call the web_search tool before answering."
                } else if currentInfoPrompt, !hasBraveKey {
                    systemText += "\nThis user is asking for current or recent information, but web search is not configured in this session. Do not claim to have browsed the web."
                }
            }
            if useDirectToolPrefetch {
                systemText += "\nA tool result is already provided in the conversation. Use it if relevant and answer directly. Do not say that you cannot browse or access the web."
            }
            chatMessages.append(.system(systemText))

            let lastIndex = messages.count - 1
            for (idx, msg) in messages.enumerated() {
                switch msg.role {
                case .system:
                    chatMessages.append(.system(msg.text))
                case .user:
                    if idx == lastIndex, model.supportsVision,
                       let uiImage = msg.image, let ciImage = CIImage(image: uiImage) {
                        chatMessages.append(.user(msg.text, images: [.ciImage(ciImage)]))
                    } else {
                        chatMessages.append(.user(msg.text))
                    }
                case .assistant:
                    chatMessages.append(.assistant(msg.text))
                case .tool:
                    chatMessages.append(.tool(msg.text))
                }
            }

            let contextSize = settings.contextSize
            let simplePrompt = Self.isSimplePrompt(text)
            let creativePrompt = Self.isCreativePrompt(text)
            let imageDescriptionPrompt = image != nil && Self.isImageDescriptionPrompt(text)
            // Tools + thinking tags burn tokens before the actual response
            let maxTokens = imageDescriptionPrompt ? min(360, contextSize / 6) :
                image != nil ? min(280, contextSize / 7) :
                (toolsActive || useDirectToolPrefetch) ? min(400, contextSize / 10) :
                simplePrompt && !thinkingEnabled ? min(48, contextSize / 24) :
                creativePrompt ? min(640, contextSize / 6) :
                thinkingEnabled ? min(1200, contextSize / 4) :
                min(160, contextSize / 16)

            // Qwen3.5 official guidance uses enable_thinking plus 0.7 / 0.8 / 1.0
            // for normal non-thinking text generation. We keep a lower temperature
            // only for trivial prompts to bias toward direct answers.
            let enableThinking: Bool? = model.isThinkingModel && model.supportsNoThink
                ? thinkingEnabled : nil
            let temperature: Float = thinkingEnabled ? 0.6 : (simplePrompt ? 0.35 : 0.7)
            let topP: Float = thinkingEnabled ? 0.95 : 0.8
            let repetitionPenalty: Float = thinkingEnabled ? 1.1 : 1.0

            // Set up streaming flag early so tool callbacks can capture it
            let streaming = settings.streamingEnabled

            // Build tools if enabled
            let toolSchemas: [ToolSpec]?
            let toolDispatch: (@Sendable (String, [String: String]) async -> (name: String, result: String, searchResults: [SearchResult]?))?

            if toolsActive && !useDirectToolPrefetch {
                let braveKey = settings.braveAPIKey
                toolSchemas = ToolRegistry.allSchemas(braveAPIKeyAvailable: hasBraveKey)
                let tipsHolder = TipsContinuationHolder()
                self.tipsContinuationHolder = tipsHolder
                toolDispatch = { @Sendable name, args in
                    if name == "tips" {
                        let result = await withTaskCancellationHandler {
                            await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                                tipsHolder.set(continuation)
                            }
                        } onCancel: {
                            tipsHolder.resume(with: "User cancelled the questionnaire.")
                        }
                        return ("tips", result, nil)
                    }
                    return await ToolRegistry.dispatchByName(
                        name: name, arguments: args,
                        braveAPIKey: hasBraveKey ? braveKey : nil
                    )
                }
            } else {
                toolSchemas = nil
                toolDispatch = nil
            }

            let onToolCall: (@MainActor @Sendable (String) -> Void)?
            if toolsActive && !useDirectToolPrefetch {
                onToolCall = { [weak self, streaming] toolName in
                    guard let self else { return }
                    // Capture the raw tool call tokens from the streaming placeholder before removing it
                    var capturedTokens: String?
                    if streaming, let idx = self.streamingMessageIndex, idx < self.messages.count {
                        let rawText = self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rawText.isEmpty {
                            capturedTokens = rawText
                        }
                        self.messages.remove(at: idx)
                        self.streamingMessageIndex = nil
                    }

                    if toolName == "tips" {
                        let query = self.messages.last(where: { $0.role == .user && !$0.isHidden })?.text
                            ?? self.messages.last(where: { $0.role == .user })?.text
                            ?? ""
                        self.presentTipsQuestionnaire(
                            for: query,
                            toolCallTokens: capturedTokens,
                            flow: .toolCall
                        )
                        return
                    }

                    let displayName = Self.toolDisplayName(toolName)
                    self.statusMessage = displayName
                    self.messages.append(
                        ChatMessage(
                            role: .tool,
                            text: "",
                            displayText: displayName,
                            toolName: toolName,
                            toolCallTokens: capturedTokens
                        )
                    )
                    self.pendingToolMessageIndex = self.messages.count - 1
                }
            } else {
                onToolCall = nil
            }

            let onToolResult: (@MainActor @Sendable (String, String, [SearchResult]?) -> Void)?
            if toolsActive && !useDirectToolPrefetch {
                onToolResult = { [weak self, streaming] toolName, result, searchResults in
                    guard let self else { return }

                    if toolName == "tips" {
                        // Tips message was already updated by handleTipsSubmit.
                        // Just create the streaming placeholder for the final response.
                        self.statusMessage = "Generating..."
                        if streaming {
                            self.messages.append(ChatMessage(role: .assistant, text: ""))
                            self.streamingMessageIndex = self.messages.count - 1
                        }
                        return
                    }

                    if let idx = self.pendingToolMessageIndex, idx < self.messages.count {
                        self.messages[idx].text = result
                        self.messages[idx].displayText = Self.toolDisplayName(toolName)
                        self.messages[idx].searchResults = searchResults
                    } else {
                        self.messages.append(
                            ChatMessage(
                                role: .tool,
                                text: result,
                                displayText: Self.toolDisplayName(toolName),
                                toolName: toolName,
                                searchResults: searchResults
                            )
                        )
                    }
                    self.pendingToolMessageIndex = nil
                    // Re-create the streaming placeholder now that the tool is done
                    // and the final response generation is about to start
                    if streaming {
                        self.messages.append(ChatMessage(role: .assistant, text: ""))
                        self.streamingMessageIndex = self.messages.count - 1
                    }
                }
            } else {
                onToolResult = nil
            }

            if let preflightTool {
                let displayName = Self.toolDisplayName(preflightTool.name)
                statusMessage = displayName
                messages.append(
                    ChatMessage(
                        role: .tool,
                        text: "",
                        displayText: displayName,
                        toolName: preflightTool.name
                    )
                )
                pendingToolMessageIndex = messages.count - 1

                let preflightResult = await ToolRegistry.dispatchByName(
                    name: preflightTool.name,
                    arguments: preflightTool.arguments,
                    braveAPIKey: hasBraveKey ? settings.braveAPIKey : nil
                )

                if let idx = pendingToolMessageIndex, idx < messages.count {
                    messages[idx].text = preflightResult.result
                    messages[idx].displayText = Self.toolDisplayName(preflightResult.name)
                    messages[idx].searchResults = preflightResult.searchResults
                }
                pendingToolMessageIndex = nil
                chatMessages.append(.tool(preflightResult.result))
            }

            // Set up streaming callback
            let onChunk: (@MainActor @Sendable (String) -> Void)?
            if streaming {
                messages.append(ChatMessage(role: .assistant, text: ""))
                streamingMessageIndex = messages.count - 1
                onChunk = { [weak self] chunk in
                    guard let self, let idx = self.streamingMessageIndex,
                          idx < self.messages.count else { return }
                    self.messages[idx].text += chunk
                    // Extract thinking content and cleaned text separately
                    let extracted = Self.extractThinkingContent(self.messages[idx].text)
                    self.messages[idx].displayText = extracted.cleaned
                    self.messages[idx].thinkingText = extracted.thinking
                }
            } else {
                onChunk = nil
            }

            let result = try await engine.generateChat(
                messages: chatMessages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                enableThinking: enableThinking,
                hasImage: image != nil,
                tools: toolSchemas,
                toolDispatch: toolDispatch,
                onToolCall: onToolCall,
                onToolResult: onToolResult,
                onChunk: onChunk
            )

            var finalOutput = Self.postProcessAssistantOutput(
                result.cleanedOutput,
                simplePrompt: simplePrompt,
                thinkingEnabled: thinkingEnabled
            )
            var finalMetrics = result.metrics

            if !thinkingEnabled,
               image == nil,
               !toolsActive,
               Self.looksLikeReasoningOnlyOutput(finalOutput)
            {
                let retrySystemText = systemText + "\nYour previous draft exposed reasoning instead of an answer. Respond again with only the user-facing answer. No preamble. No bullets. No analysis. Maximum 12 words."
                var retryMessages = chatMessages
                retryMessages[0] = .system(retrySystemText)
                let retryResult = try await engine.generateChat(
                    messages: retryMessages,
                    maxTokens: min(32, maxTokens),
                    temperature: 0.2,
                    topP: 0.7,
                    repetitionPenalty: 1.0,
                    enableThinking: false,
                    hasImage: false,
                    tools: nil,
                    toolDispatch: nil,
                    onToolCall: nil,
                    onToolResult: nil,
                    onChunk: nil
                )
                let retryOutput = Self.postProcessAssistantOutput(
                    retryResult.cleanedOutput,
                    simplePrompt: simplePrompt,
                    thinkingEnabled: false
                )
                if !retryOutput.isEmpty, !Self.looksLikeReasoningOnlyOutput(retryOutput) {
                    finalOutput = retryOutput
                    finalMetrics = retryResult.metrics
                }
            }

            if let err = result.error {
                // Remove the streaming placeholder on error
                if streaming, let idx = streamingMessageIndex, idx < messages.count {
                    messages.remove(at: idx)
                }
                removePendingToolPlaceholderIfNeeded()
                error = err
            } else if streaming, let idx = streamingMessageIndex, idx < messages.count {
                // Extract thinking from the full streamed text
                let extracted = Self.extractThinkingContent(messages[idx].text)
                let streamedOutput = extracted.cleaned
                let streamedThinking = extracted.thinking

                let shouldKeepStreamedOutput =
                    !streamedOutput.isEmpty &&
                    !Self.looksLikeReasoningOnlyOutput(streamedOutput) &&
                    streamedOutput.count > finalOutput.count + 40

                let resolvedOutput = shouldKeepStreamedOutput ? streamedOutput : finalOutput
                if Self.shouldReplaceAssistantTextWithTipsQuestionnaire(
                    userText: text,
                    assistantText: resolvedOutput,
                    hasImage: image != nil,
                    toolsEnabled: settings.toolsEnabled
                ) {
                    messages.remove(at: idx)
                    streamingMessageIndex = nil
                    presentTipsQuestionnaire(for: text, flow: .syntheticFollowUp)
                } else {
                    messages[idx].text = resolvedOutput
                    messages[idx].displayText = nil
                    messages[idx].thinkingText = streamedThinking
                    messages[idx].metrics = finalMetrics
                }
            } else {
                // Non-streaming: extract thinking from the raw output
                let extracted = Self.extractThinkingContent(result.output)
                if Self.shouldReplaceAssistantTextWithTipsQuestionnaire(
                    userText: text,
                    assistantText: finalOutput,
                    hasImage: image != nil,
                    toolsEnabled: settings.toolsEnabled
                ) {
                    presentTipsQuestionnaire(for: text, flow: .syntheticFollowUp)
                } else {
                    messages.append(ChatMessage(
                        role: .assistant,
                        text: finalOutput,
                        thinkingText: extracted.thinking,
                        metrics: finalMetrics
                    ))
                }
            }

            streamingMessageIndex = nil
        } catch is CancellationError {
            // Stopped by user — no error to show
            finalizeStreamingMessageAfterInterruption()
            removePendingToolPlaceholderIfNeeded()
        } catch {
            finalizeStreamingMessageAfterInterruption()
            self.error = Self.userFacingGenerationError(
                from: error,
                model: model,
                requestedVision: needsVision,
                settings: settings
            )
            if needsVision || Self.isLikelyMemoryPressureError(error) {
                releaseEngineAfterFailure()
            }
            removePendingToolPlaceholderIfNeeded()
        }

        statusMessage = nil
        isGenerating = false
        currentGenerationUsesVision = false
    }

    func stopGeneration() {
        // Resume any pending tips continuation before cancelling the task
        tipsContinuationHolder?.resume(with: "User cancelled the questionnaire.")
        tipsContinuationHolder = nil
        pendingTipsMessageIndex = nil
        pendingTipsFlow = nil

        generationTask?.cancel()
        generationTask = nil

        // Finalize any streaming message with whatever text was generated so far
        finalizeStreamingMessageAfterInterruption()
        removePendingToolPlaceholderIfNeeded()
        statusMessage = nil
        isGenerating = false
        currentGenerationUsesVision = false
    }

    func clearSession() {
        stopGeneration()
        messages = []
        error = nil
        productQuestionnaireShown = false
        pendingQuestionnaireMessageIndex = nil
        tipsContinuationHolder?.resume(with: "User cancelled the questionnaire.")
        tipsContinuationHolder = nil
        pendingTipsMessageIndex = nil
        pendingTipsFlow = nil
    }

    /// Handle a completed tips questionnaire: update the message and resume the tool continuation.
    func handleTipsSubmit(_ filled: TipsQuestionnaire) {
        if let idx = pendingTipsMessageIndex, idx < messages.count {
            var submitted = filled
            submitted.isSubmitted = true
            messages[idx].tipsQuestionnaire = submitted
            messages[idx].text = filled.toToolResult()
        }
        pendingTipsMessageIndex = nil

        let toolResult = filled.toToolResult()
        let flow = pendingTipsFlow
        pendingTipsFlow = nil

        switch flow {
        case .syntheticFollowUp:
            tipsContinuationHolder = nil
            generationTask = Task { [weak self] in
                await self?.sendMessage(
                    text: Self.syntheticTipsFollowUpPrompt(from: filled),
                    image: nil,
                    displayUserMessage: false
                )
            }
        case .toolCall, .none:
            tipsContinuationHolder?.resume(with: toolResult)
            tipsContinuationHolder = nil
        }
    }

    /// Check if this is a first-time product query that should show the questionnaire.
    func shouldShowProductQuestionnaire(for text: String, hasImage: Bool) -> Bool {
        guard !productQuestionnaireShown,
              !hasImage,
              SettingsManager.shared.toolsEnabled,
              Self.isProductQuery(text) else {
            return false
        }
        return true
    }

    /// Insert a questionnaire message into the chat.
    func showProductQuestionnaire(for text: String) {
        productQuestionnaireShown = true
        let questionnaire = ProductQuestionnaire(originalQuery: text)
        let msg = ChatMessage(
            role: .assistant,
            text: "",
            questionnaire: questionnaire
        )
        messages.append(msg)
        pendingQuestionnaireMessageIndex = messages.count - 1
    }

    /// Handle a completed questionnaire: update the message, build a refined query, and search.
    func handleQuestionnaireSubmit(_ filled: ProductQuestionnaire) {
        // Update the questionnaire message to show submitted state
        if let idx = pendingQuestionnaireMessageIndex, idx < messages.count {
            var summary = "Query: \(filled.originalQuery)"
            if filled.priceRange.lowerBound > 0 || filled.priceRange.upperBound < 5000 {
                summary += " | Price: $\(Int(filled.priceRange.lowerBound))-$\(Int(filled.priceRange.upperBound))"
            }
            if !filled.brand.isEmpty {
                summary += " | Brand: \(filled.brand)"
            }
            if filled.condition != "Any" {
                summary += " | Condition: \(filled.condition)"
            }
            if filled.sortBy != "Relevance" {
                summary += " | Sort: \(filled.sortBy)"
            }
            var submittedQ = filled
            submittedQ.isSubmitted = true
            messages[idx].questionnaire = submittedQ
            messages[idx].text = summary
        }
        pendingQuestionnaireMessageIndex = nil

        // Build a refined query from the questionnaire answers
        var refinedQuery = filled.originalQuery
        if !filled.brand.isEmpty {
            refinedQuery += " \(filled.brand)"
        }
        if filled.condition != "Any" {
            refinedQuery += " \(filled.condition.lowercased())"
        }
        if filled.priceRange.lowerBound > 0 || filled.priceRange.upperBound < 5000 {
            refinedQuery += " $\(Int(filled.priceRange.lowerBound))-$\(Int(filled.priceRange.upperBound))"
        }

        // Now trigger the actual product search + model response with the refined query
        generationTask = Task {
            await sendMessage(text: refinedQuery, image: nil)
        }
    }

    private static func stripThinkingTags(_ text: String) -> String {
        return extractThinkingContent(text).cleaned
    }

    /// Extracts thinking content and cleaned text from raw model output.
    /// Returns (thinking text or nil, cleaned response text).
    private static func extractThinkingContent(_ text: String) -> (thinking: String?, cleaned: String) {
        var cleaned = text
        var thinkingParts: [String] = []

        // Extract matched <think>...</think> pairs
        let pattern = #"<think>([\s\S]*?)</think>"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = regex.matches(in: cleaned, range: range)
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: cleaned) {
                    let content = String(cleaned[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        thinkingParts.append(content)
                    }
                }
            }
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Handle orphaned </think>
        if let closeRange = cleaned.range(of: "</think>") {
            let before = String(cleaned[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(cleaned[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                thinkingParts.append(before)
            }
            if after.count >= 2 {
                cleaned = after
            } else {
                cleaned = cleaned.replacingOccurrences(of: "</think>", with: "")
            }
        }

        // Handle orphaned <think> (still generating thinking)
        if let openRange = cleaned.range(of: "<think>") {
            let before = String(cleaned[..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(cleaned[openRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty {
                thinkingParts.append(after)
            }
            if before.count >= 2 {
                cleaned = before
            } else {
                cleaned = ""
            }
        }

        let thinking = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n")
        return (thinking, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func postProcessAssistantOutput(
        _ text: String,
        simplePrompt: Bool,
        thinkingEnabled: Bool
    ) -> String {
        let cleaned = stripThinkingTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !thinkingEnabled else { return cleaned }

        if let leaked = salvageFromReasoningLeak(cleaned, simplePrompt: simplePrompt) {
            return leaked
        }

        return cleaned
    }

    private static func salvageFromReasoningLeak(_ text: String, simplePrompt: Bool) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let reasoningKeywords = [
            "thinking process", "analyze the", "analyze the request", "analyze the input",
            "constraint:", "decision:", "re-evaluating", "let's ", "however", "since ",
            "wait", "actually", "i should", "i can", "i need to", "for simple questions"
        ]

        let reasoningLineCount = lines.filter { line in
            let lower = line.lowercased()
            return lower.hasPrefix("*") ||
                lower.hasPrefix("-") ||
                lower.contains("constraint:") ||
                reasoningKeywords.contains(where: { lower.contains($0) })
        }.count

        let looksLikeReasoningLeak = reasoningLineCount >= 2 ||
            reasoningKeywords.contains(where: { text.lowercased().contains($0) }) ||
            text.contains("Constraint:")
        guard looksLikeReasoningLeak else { return nil }

        if let quoted = lastQuotedSentence(in: text) {
            return quoted
        }

        let candidateLines = lines.filter { line in
            let lower = line.lowercased()
            guard !lower.hasPrefix("*"), !lower.hasPrefix("-") else { return false }
            guard !reasoningKeywords.contains(where: { lower.contains($0) }) else { return false }
            guard !lower.contains("constraint:"), !lower.contains("decision:") else { return false }
            return line.count <= (simplePrompt ? 90 : 180)
        }

        return candidateLines.last
    }

    private static func looksLikeReasoningOnlyOutput(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let markers = [
            "thinking process", "analyze the request", "analyze the input",
            "constraint:", "decision:", "re-evaluating", "let's ",
            "i should", "i need to", "for simple questions"
        ]
        if markers.contains(where: { normalized.contains($0) }) {
            return true
        }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let bulletLikeLines = lines.filter {
            $0.hasPrefix("1.") || $0.hasPrefix("2.") || $0.hasPrefix("*") || $0.hasPrefix("-")
        }
        let analyticalBulletLines = bulletLikeLines.filter { line in
            markers.contains(where: { line.contains($0) })
        }
        if !analyticalBulletLines.isEmpty && analyticalBulletLines.count * 2 >= max(1, bulletLikeLines.count) {
            return true
        }
        return false
    }

    private static func lastQuotedSentence(in text: String) -> String? {
        let pattern = #""([^"\n]{2,160}[.!?])""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }

    private func presentTipsQuestionnaire(
        for query: String,
        toolCallTokens: String? = nil,
        flow: PendingTipsFlow
    ) {
        let questionnaire = TipsQuestionnaire(originalQuery: query)
        messages.append(ChatMessage(
            role: .assistant,
            text: "",
            toolCallTokens: toolCallTokens,
            tipsQuestionnaire: questionnaire
        ))
        pendingTipsMessageIndex = messages.count - 1
        pendingTipsFlow = flow
        statusMessage = nil
    }

    private static func shouldReplaceAssistantTextWithTipsQuestionnaire(
        userText: String,
        assistantText: String,
        hasImage: Bool,
        toolsEnabled: Bool
    ) -> Bool {
        guard toolsEnabled, !hasImage else { return false }

        let assistant = assistantText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userText.lowercased()
        guard !assistant.isEmpty else { return false }

        let shoppingSignals = [
            "buy", "shop", "purchase", "recommend", "best", "compare", "looking for",
            "find me", "find a", "which one", "good option", "product"
        ]
        let preferenceSignals = [
            "budget", "price range", "how much", "spend", "brand", "features",
            "priorities", "use case", "what is this for", "what's this for",
            "condition", "new or used", "preference", "preferences", "matters most"
        ]
        let questionSignals = [
            "?", "could you share", "please share", "let me know",
            "tell me", "do you have", "would you like"
        ]

        let isShoppingContext = shoppingSignals.contains { user.contains($0) }
        let asksPreferenceQuestion = preferenceSignals.contains { assistant.contains($0) } &&
            questionSignals.contains { assistant.contains($0) }

        return isShoppingContext && asksPreferenceQuestion
    }

    private static func syntheticTipsFollowUpPrompt(from questionnaire: TipsQuestionnaire) -> String {
        """
        Continue helping with the earlier shopping request. The user completed the interactive questionnaire, so do not ask more preference questions in text unless absolutely necessary. Use these preferences to search or recommend products.

        \(questionnaire.toToolResult())
        """
    }

    private func removePendingToolPlaceholderIfNeeded() {
        if let idx = pendingToolMessageIndex, idx < messages.count, messages[idx].text.isEmpty {
            messages.remove(at: idx)
        }
        pendingToolMessageIndex = nil
    }

    private func finalizeStreamingMessageAfterInterruption() {
        if let idx = streamingMessageIndex, idx < messages.count {
            let rawText = messages[idx].text
            let extracted = Self.extractThinkingContent(rawText)
            if extracted.cleaned.isEmpty && extracted.thinking == nil {
                messages.remove(at: idx)
            } else {
                messages[idx].text = extracted.cleaned
                messages[idx].displayText = nil
                messages[idx].thinkingText = extracted.thinking
            }
        }
        streamingMessageIndex = nil
    }

    private func handleMemoryWarning() {
        let wasGenerating = isGenerating
        let usedVision = currentGenerationUsesVision

        if wasGenerating {
            stopGeneration()
            error = usedVision
                ? "Vision generation was stopped because the device is low on memory. Try a smaller model, lower `GPU Memory Limit`, or reduce `Max Image Dimension` in Settings."
                : "Generation was stopped because the device is low on memory. Try a smaller model or a lower `GPU Memory Limit`."
            releaseEngineAfterFailure()
            return
        }

        error = "The device reported low memory. The current model may need to be reloaded before the next message."
    }

    private func releaseEngineAfterFailure() {
        let sharedEngine = SettingsManager.shared.sharedEngine
        guard let sharedEngine else { return }

        Task {
            await sharedEngine.unloadModel()
            await MainActor.run {
                SettingsManager.shared.sharedEngine = nil
            }
        }
    }

    private func visionPreflightFailure(
        for model: ModelSpec,
        image: UIImage?,
        settings: SettingsManager
    ) -> String? {
        guard let image else { return nil }

        let imagePixels = Double(image.size.width * image.size.height)
        let imageWorkingSetGB = max(0.12, (imagePixels * 4 * 3) / 1_073_741_824)
        let estimatedRequiredGB = max(
            model.sizeGB * 1.35 + 0.6,
            model.sizeGB + 1.4 + imageWorkingSetGB
        )
        let safeDeviceBudgetGB = max(0, settings.availableMemoryGB - 0.5)
        let safeGPUBudgetGB = max(0, Double(settings.gpuMemoryLimitGB) - 0.25)
        let effectiveBudgetGB = min(safeDeviceBudgetGB, safeGPUBudgetGB)

        guard estimatedRequiredGB > effectiveBudgetGB else { return nil }

        let recommendedLimitGB = Int(ceil(estimatedRequiredGB))
        return """
        Not enough memory for vision with \(model.displayName). Estimated need: \(Self.formatGB(estimatedRequiredGB)); available budget: \(Self.formatGB(effectiveBudgetGB)). Try a smaller model, set `GPU Memory Limit` to at least \(recommendedLimitGB) GB if the device allows it, or reduce `Max Image Dimension`.
        """
    }

    private static func userFacingGenerationError(
        from error: Error,
        model: ModelSpec,
        requestedVision: Bool,
        settings: SettingsManager
    ) -> String {
        if isLikelyMemoryPressureError(error) {
            if requestedVision {
                return "Vision generation failed because the device ran out of memory for \(model.displayName). Try a smaller model, a lower `GPU Memory Limit`, or a smaller image."
            }
            return "Generation failed because the device ran out of memory for \(model.displayName). Try a smaller model or lower the `GPU Memory Limit`."
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if requestedVision {
            return message.isEmpty
                ? "Vision generation failed for \(model.displayName). The model was unloaded so the app can recover cleanly."
                : "Vision generation failed for \(model.displayName): \(message)"
        }

        return message.isEmpty
            ? "Generation failed for \(model.displayName)."
            : message
    }

    private static func isLikelyMemoryPressureError(_ error: Error) -> Bool {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        let markers = [
            "out of memory",
            "not enough memory",
            "insufficient memory",
            "memory limit",
            "failed to allocate",
            "allocation failed",
            "resource exhausted",
            "heap",
            "buffer",
            "metal"
        ]
        return markers.contains { text.contains($0) }
    }

    private static func formatGB(_ value: Double) -> String {
        String(format: "%.1f GB", max(0, value))
    }

    private static func shouldEnableTools(for text: String, hasImage: Bool, toolsEnabled: Bool) -> Bool {
        guard toolsEnabled, !hasImage else { return false }

        let normalized = text.lowercased()
        if normalized.contains("http://") || normalized.contains("https://") || normalized.contains("www.") {
            return true
        }

        let triggers = [
            "latest", "current", "today", "recent", "news", "headline", "weather", "forecast",
            "search", "look up", "lookup", "find online", "browse", "website", "web page",
            "article", "url", "link", "stock price", "price of", "score", "exchange rate",
            "buy", "shop", "purchase", "order", "product", "where can i find", "where to buy",
            "best deal", "cheapest", "recommendation", "recommend me"
        ]
        return triggers.contains { normalized.contains($0) }
    }

    private static func isProductQuery(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let triggers = [
            "buy", "shop", "purchase", "order online", "where to buy", "where can i buy",
            "where can i find", "best deal", "cheapest", "on sale", "discount",
            "recommend a product", "recommend me a", "looking for a product",
            "find me a", "search for product"
        ]
        return triggers.contains { normalized.contains($0) }
    }

    private static func requiresCurrentInfo(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let triggers = [
            "latest", "current", "today", "recent", "news", "headline",
            "just happened", "what's happening", "what is happening", "update"
        ]
        return triggers.contains { normalized.contains($0) }
    }

    private struct PreflightToolCall {
        let name: String
        let arguments: [String: String]
    }

    private static func preflightToolCall(
        for text: String,
        hasImage: Bool,
        toolsEnabled: Bool,
        braveAPIKeyAvailable: Bool
    ) -> PreflightToolCall? {
        guard shouldEnableTools(for: text, hasImage: hasImage, toolsEnabled: toolsEnabled) else {
            return nil
        }

        if let url = firstURL(in: text) {
            return PreflightToolCall(name: "url_fetch", arguments: ["url": url])
        }

        if Self.isProductQuery(text) {
            return PreflightToolCall(name: "product_search", arguments: ["query": text])
        }

        if braveAPIKeyAvailable, requiresCurrentInfo(text) {
            return PreflightToolCall(name: "web_search", arguments: ["query": text])
        }

        return nil
    }

    private static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches {
            guard let url = match.url?.absoluteString else { continue }
            if url.hasPrefix("http://") || url.hasPrefix("https://") {
                return url
            }
        }
        return nil
    }

    private static func isSimplePrompt(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 24 {
            let simplePhrases = [
                "hi", "hello", "hey", "yo", "sup", "thanks", "thank you",
                "ok", "okay", "cool", "nice", "great", "morning", "good morning",
                "afternoon", "good afternoon", "evening", "good evening"
            ]
            if simplePhrases.contains(normalized) {
                return true
            }
        }
        return normalized.count <= 40 &&
            !normalized.contains("?") &&
            !normalized.contains("http://") &&
            !normalized.contains("https://")
    }

    private static func isCreativePrompt(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let triggers = [
            "write a story", "tell me a story", "story about", "short story",
            "write me", "write an", "write about", "fiction", "fairy tale",
            "bedtime story", "poem", "haiku", "sonnet", "scene", "chapter"
        ]

        return triggers.contains { normalized.contains($0) }
    }

    private static func isImageDescriptionPrompt(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let triggers = [
            "describe the image", "describe this image", "what's in this image",
            "what is in this image", "what's in the picture", "what is in the picture",
            "describe the picture", "analyze this image", "analyse this image",
            "caption this image"
        ]

        return triggers.contains { normalized.contains($0) }
    }


    private static func toolDisplayName(_ name: String) -> String {
        switch name {
        case "web_search": return "Searching the web..."
        case "product_search": return "Searching for products..."
        case "url_fetch": return "Fetching URL..."
        case "tips": return "Gathering preferences..."
        default: return "Using \(name)..."
        }
    }

    private func resizeImage(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxEdge else { return image }

        let scale = maxEdge / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func compressImage(_ image: UIImage, quality: Double) -> UIImage? {
        guard let data = image.jpegData(compressionQuality: CGFloat(quality)) else { return image }
        return UIImage(data: data) ?? image
    }
}
