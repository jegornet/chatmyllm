//
//  ChatDetailView.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var chat: Chat

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSettingsAlert: Bool = false
    @State private var streamingContent: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var streamingChatId: UUID? = nil
    @State private var lastScrollTime: Date = .distantPast

    @Environment(SettingsManager.self) private var settings
    @FocusState private var isInputFocused: Bool
    @State private var availableModels: [OpenRouterModel] = []
    @State private var isLoadingModels = false

    var sortedMessages: [Message] {
        chat.messages.sorted { $0.timestamp < $1.timestamp }
    }

    var enabledAvailableModels: [OpenRouterModel] {
        availableModels.filter { settings.enabledModels.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedMessages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Processing...", comment: "Loading indicator text")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .id("loading")
                            }
                        }

                        // Streaming view OUTSIDE LazyVStack to avoid prefetch conflicts
                        if isStreaming && streamingChatId == chat.id {
                            StreamingMessageView(content: streamingContent)
                                .id("streaming")
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .scrollIndicators(isStreaming && streamingChatId == chat.id ? .hidden : .visible)
                .defaultScrollAnchor(.bottom)
                .id(chat.id)
                .onChange(of: streamingContent) { oldValue, newValue in
                    // Auto-scroll during streaming with throttling
                    // Safe now because StreamingMessageView is outside LazyVStack
                    if isStreaming && streamingChatId == chat.id {
                        let now = Date()
                        if now.timeIntervalSince(lastScrollTime) > 0.3 {
                            lastScrollTime = now
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }

            // Input area
            VStack(spacing: 8) {
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button(String(localized: "Close", comment: "Close error button")) {
                            errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $chat.draft)
                        .font(settings.customFont)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .focused($isInputFocused)
                        .onKeyPress { press in
                            // Only handle return key
                            if press.key == .return {
                                // Check if shift is pressed
                                if press.modifiers.contains(.shift) {
                                    // Shift is pressed, allow new line
                                    return .ignored
                                }
                                // Don't send during streaming in THIS chat
                                if isStreaming && streamingChatId == chat.id {
                                    return .handled
                                }
                                // No shift, send message if not empty
                                if !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sendMessage()
                                }
                                return .handled
                            }
                            return .ignored
                        }

                    if isStreaming && streamingChatId == chat.id {
                        Button(action: stopStreaming) {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.blue)
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .help("Stop generation")
                    }
                }
                .padding()
            }
        }
        .navigationTitle(chat.title)
        .toolbarBackground(Color(nsColor: .controlBackgroundColor).opacity(0.88), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else if !enabledAvailableModels.isEmpty {
                    Picker("", selection: $chat.modelId) {
                        ForEach(enabledAvailableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                    .disabled(isStreaming)
                } else {
                    Text("No models available", comment: "No models message")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .alert(String(localized: "API Key Required", comment: "Alert title"), isPresented: $showSettingsAlert) {
            Button(String(localized: "Open Settings", comment: "Open settings button")) {
                openSettings()
            }
            Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text("Please set OpenRouter API key in settings", comment: "Alert message")
        }
        .onAppear {
            // Load available models
            Task {
                await loadModels()
            }

            // Auto-send if last message is from user (new chat from EmptyStateView or quick chat)
            checkAndAutoSend()
        }
        .onDisappear {
            // Cancel streaming when view disappears (chat switched)
            if isStreaming && streamingChatId == chat.id {
                streamingTask?.cancel()
                streamingTask = nil

                // Save partial response if any to the current chat
                if !streamingContent.isEmpty {
                    let assistantMessage = Message(content: streamingContent, isFromUser: false, chat: chat)
                    chat.messages.append(assistantMessage)
                    modelContext.insert(assistantMessage)
                }

                isStreaming = false
                streamingContent = ""
                streamingChatId = nil
            }
        }
        .onChange(of: chat.id) { oldValue, newValue in
            // Set focus when chat changes
            isInputFocused = true

            // Also check auto-send when chat changes (e.g., from quick chat)
            checkAndAutoSend()
        }
    }

    private func loadModels() async {
        guard availableModels.isEmpty else { return }

        isLoadingModels = true
        do {
            let models = try await OpenRouterService.shared.fetchModels()
            await MainActor.run {
                availableModels = models
                isLoadingModels = false
            }
        } catch {
            await MainActor.run {
                isLoadingModels = false
            }
        }
    }

    private func checkAndAutoSend() {
        let shouldAutoSend = sortedMessages.last?.isFromUser == true && !isStreaming
        if shouldAutoSend {
            sendMessage(autoSend: true)
        } else {
            // Set focus on input field when opening existing chat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }

    private func sendMessage(autoSend: Bool = false) {
        // For auto-send, we don't check draft - message is already in chat.messages
        if !autoSend {
            guard !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        }

        // Check API key
        if !settings.hasApiKey {
            showSettingsAlert = true
            return
        }

        // Set streaming state immediately before any UI updates
        errorMessage = nil
        streamingContent = ""
        isStreaming = true
        streamingChatId = chat.id
        lastScrollTime = .distantPast

        let currentMessage: String
        if !autoSend {
            // Manual send - create user message from draft
            let userMessage = Message(content: chat.draft, isFromUser: true, chat: chat)
            chat.messages.append(userMessage)
            modelContext.insert(userMessage)
            currentMessage = chat.draft
            chat.draft = ""

        } else {
            // Auto-send - message already exists, get it for title update
            currentMessage = sortedMessages.last?.content ?? ""
        }

        streamingTask = Task {
            do {
                try await OpenRouterService.shared.sendMessageStreaming(
                    messages: chat.messages,
                    model: chat.modelId
                ) { chunk in
                    streamingContent += chunk
                }

                await MainActor.run {
                    var finalMessageId: UUID? = nil

                    // Only save if not cancelled
                    if !streamingContent.isEmpty {
                        // Create the final message with the complete streamed content
                        let assistantMessage = Message(content: streamingContent, isFromUser: false, chat: chat)
                        chat.messages.append(assistantMessage)
                        modelContext.insert(assistantMessage)
                        finalMessageId = assistantMessage.id

                        // Update chat title with first message if needed
                        let newChatTitle = String(localized: "New Chat", comment: "Default chat title")
                        if chat.title == newChatTitle && !currentMessage.isEmpty {
                            let title = String(currentMessage.prefix(50))
                            chat.title = title
                        }
                    }

                    isStreaming = false
                    streamingContent = ""
                    streamingTask = nil
                    streamingChatId = nil

                    // Scroll to final message after streaming completes
                    if let messageId = finalMessageId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy?.scrollTo(messageId, anchor: .bottom)
                            }
                        }
                    }

                    // Restore focus to input field
                    isInputFocused = true
                }
            } catch {
                await MainActor.run {
                    // Don't show error if task was cancelled
                    if !Task.isCancelled {
                        errorMessage = error.localizedDescription
                    }
                    isStreaming = false
                    streamingContent = ""
                    streamingTask = nil
                    streamingChatId = nil

                    // Restore focus to input field
                    isInputFocused = true
                }
            }
        }
    }

    private func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        var finalMessageId: UUID? = nil

        // Save partial response if any
        if !streamingContent.isEmpty {
            let assistantMessage = Message(content: streamingContent, isFromUser: false, chat: chat)
            chat.messages.append(assistantMessage)
            modelContext.insert(assistantMessage)
            finalMessageId = assistantMessage.id
        }

        isStreaming = false
        streamingContent = ""
        streamingChatId = nil

        // Scroll to final message after stopping
        if let messageId = finalMessageId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy?.scrollTo(messageId, anchor: .bottom)
                }
            }
        }

        // Restore focus to input field after stopping
        isInputFocused = true
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

struct MessageBubbleView: View {
    let message: Message
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        HStack(alignment: .top) {
            if message.isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                MarkdownText(content: message.content, fontName: settings.fontName, fontSize: settings.fontSize, lineSpacing: settings.lineSpacing, isFromUser: message.isFromUser)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(message.isFromUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                Text(message.timestamp, format: .dateTime)
                    .font(.custom(settings.fontName, size: settings.fontSize * 0.7))
                    .foregroundColor(.secondary)
                    .padding(.leading, 10)
            }

            if !message.isFromUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct MarkdownText: View {
    let content: String
    let fontName: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let isFromUser: Bool

    var body: some View {
        let parts = parseMarkdown(content)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                switch part {
                case .text(let text):
                    formatText(text)
                        .font(.custom(fontName, size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundColor(isFromUser ? .white : .primary)
                case .codeBlock(let code, _):
                    formatCodeBlock(code)
                        .font(.custom(fontName, size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundColor(isFromUser ? .white : .primary)
                case .inlineCode(let code):
                    formatInlineCode(code)
                        .font(.custom(fontName, size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundColor(isFromUser ? .white : .primary)
                case .heading(let text, let level):
                    formatHeading(text, level: level)
                        .foregroundColor(isFromUser ? .white : .primary)
                case .table(let headers, let rows):
                    formatTable(headers: headers, rows: rows)
                }
            }
        }
    }

    private func formatText(_ text: String) -> Text {
        do {
            let attributedString = try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )

            // Build Text manually with proper modifiers
            var result = Text("")

            for run in attributedString.runs {
                let content = String(attributedString[run.range].characters)
                var textSegment = Text(content)

                if let inlinePresentationIntent = run.inlinePresentationIntent {
                    // Apply semibold for bold text
                    if inlinePresentationIntent.contains(.stronglyEmphasized) {
                        textSegment = textSegment.fontWeight(.semibold)
                    }
                    // Keep italic as is
                    if inlinePresentationIntent.contains(.emphasized) {
                        textSegment = textSegment.italic()
                    }
                }

                result = result + textSegment
            }

            return result

        } catch {
            return Text(text)
        }
    }

    private func formatCodeBlock(_ code: String) -> Text {
        Text(code)
            .font(.system(size: fontSize - 1, design: .monospaced))
            .foregroundColor(isFromUser ? Color.white.opacity(0.95) : .primary)
    }

    private func formatInlineCode(_ code: String) -> Text {
        Text(code)
            .font(.system(size: fontSize - 1, design: .monospaced))
            .foregroundColor(isFromUser ? Color.white.opacity(0.95) : .primary)
    }

    private func formatHeading(_ text: String, level: Int) -> Text {
        let headingSizes: [Int: CGFloat] = [
            1: fontSize * 1.3,
            2: fontSize * 1.2,
            3: fontSize * 1.15,
            4: fontSize * 1.1,
            5: fontSize * 1.05,
            6: fontSize * 1.0
        ]

        let headingSize = headingSizes[level] ?? fontSize

        return Text(text)
                .font(.custom(fontName, size: headingSize))
                .fontWeight(Font.Weight.semibold)
    }

    private func formatTable(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    formatText(header.trimmingCharacters(in: .whitespaces))
                        .font(.custom(fontName, size: fontSize))
                        .fontWeight(.semibold)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .foregroundColor(isFromUser ? .white : .primary)
                }
            }

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        formatText(cell.trimmingCharacters(in: .whitespaces))
                            .font(.custom(fontName, size: fontSize))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundColor(isFromUser ? .white : .primary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func parseMarkdown(_ markdown: String) -> [MarkdownPart] {
        var parts: [MarkdownPart] = []
        var currentText = ""
        var position = markdown.startIndex

        while position < markdown.endIndex {
            // Check if we're at the start of a line for heading detection
            let isLineStart = position == markdown.startIndex || markdown[markdown.index(before: position)] == "\n"

            // Check for tables at the start of a line
            if isLineStart && markdown[position] == "|" {
                // Try to parse table
                if let tableResult = extractTable(from: markdown, startingAt: position) {
                    // Save accumulated text
                    if !currentText.isEmpty {
                        parts.append(.text(currentText))
                        currentText = ""
                    }

                    parts.append(.table(headers: tableResult.headers, rows: tableResult.rows))
                    position = tableResult.end
                    continue
                }
            }

            // Check for headings at the start of a line
            if isLineStart && markdown[position] == "#" {
                // Save accumulated text
                if !currentText.isEmpty {
                    parts.append(.text(currentText))
                    currentText = ""
                }

                // Count number of # symbols
                var hashCount = 0
                var tempPos = position
                while tempPos < markdown.endIndex && markdown[tempPos] == "#" && hashCount < 6 {
                    hashCount += 1
                    tempPos = markdown.index(after: tempPos)
                }

                // Check if there's a space after the hashes
                if tempPos < markdown.endIndex && markdown[tempPos] == " " {
                    // Skip the space
                    tempPos = markdown.index(after: tempPos)

                    // Extract heading text until end of line
                    let headingStart = tempPos
                    while tempPos < markdown.endIndex && markdown[tempPos] != "\n" {
                        tempPos = markdown.index(after: tempPos)
                    }

                    let headingText = String(markdown[headingStart..<tempPos]).trimmingCharacters(in: .whitespaces)
                    parts.append(.heading(headingText, level: hashCount))
                    position = tempPos
                    continue
                }
            }

            // Check for code blocks with triple backticks
            if markdown[position...].hasPrefix("```") {
                // Save accumulated text
                if !currentText.isEmpty {
                    parts.append(.text(currentText))
                    currentText = ""
                }

                // Find the end of the code block
                if let codeBlockRange = extractCodeBlock(from: markdown, startingAt: position) {
                    let codeContent = String(markdown[codeBlockRange.content])
                    parts.append(.codeBlock(codeContent, language: codeBlockRange.language))
                    position = codeBlockRange.end
                    continue
                }
            }

            // Check for inline code with single backticks
            if markdown[position] == "`" && !markdown[position...].hasPrefix("```") {
                // Save accumulated text
                if !currentText.isEmpty {
                    parts.append(.text(currentText))
                    currentText = ""
                }

                // Find the closing backtick
                var nextPos = markdown.index(after: position)
                while nextPos < markdown.endIndex && markdown[nextPos] != "`" {
                    nextPos = markdown.index(after: nextPos)
                }

                if nextPos < markdown.endIndex {
                    let codeContent = String(markdown[markdown.index(after: position)..<nextPos])
                    parts.append(.inlineCode(codeContent))
                    position = markdown.index(after: nextPos)
                    continue
                }
            }

            currentText.append(markdown[position])
            position = markdown.index(after: position)
        }

        // Add any remaining text
        if !currentText.isEmpty {
            parts.append(.text(currentText))
        }

        return parts.isEmpty ? [.text(markdown)] : parts
    }

    private func extractCodeBlock(from markdown: String, startingAt position: String.Index) -> (content: Range<String.Index>, language: String?, end: String.Index)? {
        var currentPos = markdown.index(position, offsetBy: 3) // Skip ```

        // Skip language identifier if present
        var language: String?
        var lineStart = currentPos
        while currentPos < markdown.endIndex && markdown[currentPos] != "\n" {
            currentPos = markdown.index(after: currentPos)
        }

        if currentPos > lineStart {
            language = String(markdown[lineStart..<currentPos]).trimmingCharacters(in: .whitespaces)
            if !language!.isEmpty {
                // Language found
            } else {
                language = nil
            }
        }

        if currentPos < markdown.endIndex {
            currentPos = markdown.index(after: currentPos) // Skip newline
        }

        let contentStart = currentPos

        // Find closing ```
        while currentPos < markdown.endIndex {
            if markdown[currentPos...].hasPrefix("```") {
                let contentEnd = currentPos
                let endPos = markdown.index(currentPos, offsetBy: 3, limitedBy: markdown.endIndex) ?? markdown.endIndex

                return (content: contentStart..<contentEnd, language: language, end: endPos)
            }
            currentPos = markdown.index(after: currentPos)
        }

        // No closing ``` found, treat rest as code
        return (content: contentStart..<markdown.endIndex, language: language, end: markdown.endIndex)
    }

    private func extractTable(from markdown: String, startingAt position: String.Index) -> (headers: [String], rows: [[String]], end: String.Index)? {
        var currentPos = position
        var lines: [String] = []

        // Collect all consecutive lines starting with |
        while currentPos < markdown.endIndex {
            // Check if line starts with |
            if markdown[currentPos] != "|" {
                break
            }

            // Extract line until newline or end
            let lineStart = currentPos
            while currentPos < markdown.endIndex && markdown[currentPos] != "\n" {
                currentPos = markdown.index(after: currentPos)
            }

            let line = String(markdown[lineStart..<currentPos]).trimmingCharacters(in: .whitespaces)
            lines.append(line)

            // Skip newline if present
            if currentPos < markdown.endIndex && markdown[currentPos] == "\n" {
                currentPos = markdown.index(after: currentPos)
            }
        }

        // Need at least 3 lines: header, separator, data
        guard lines.count >= 3 else {
            return nil
        }

        // Parse header row
        let headerLine = lines[0]
        let headers = headerLine.split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip separator line (line 1)
        // Parse data rows (from line 2 onwards)
        var rows: [[String]] = []
        for i in 2..<lines.count {
            let dataLine = lines[i]
            let cells = dataLine.split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        return (headers: headers, rows: rows, end: currentPos)
    }
}

enum MarkdownPart {
    case text(String)
    case codeBlock(String, language: String?)
    case inlineCode(String)
    case heading(String, level: Int)
    case table(headers: [String], rows: [[String]])
}

struct StreamingMessageView: View {
    let content: String
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if !content.isEmpty {
                    MarkdownText(
                        content: content,
                        fontName: settings.fontName,
                        fontSize: settings.fontSize,
                        lineSpacing: settings.lineSpacing,
                        isFromUser: false
                    )
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                } else {
                    // Show a typing indicator when streaming has started but no content yet
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing...", comment: "Loading indicator text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                }
            }

            Spacer(minLength: 60)
        }
    }
}
