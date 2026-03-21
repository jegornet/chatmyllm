//
//  ContentView.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026..
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedChat: Chat?
    @State private var settings = SettingsManager.shared

    var canCreateNewChat: Bool {
        // Can create new chat if no chat is selected, or if selected chat has messages
        selectedChat == nil || !(selectedChat?.messages.isEmpty ?? true)
    }

    var body: some View {
        NavigationSplitView {
            ChatListView(selectedChat: $selectedChat)
        } detail: {
            if let chat = selectedChat {
                ChatDetailView(chat: chat)
            } else {
                EmptyStateView(selectedChat: $selectedChat)
            }
        }
        .focusedValue(\.newChatAction, NewChatAction(action: addNewChat, canCreate: canCreateNewChat))
        .onReceive(NotificationCenter.default.publisher(for: .createQuickChat)) { notification in
            if let messageText = notification.userInfo?["messageText"] as? String {
                createChatWithMessage(messageText)
            }
        }
    }

    private func addNewChat() {
        withAnimation {
            let newChat = Chat(modelId: settings.defaultModelId)
            modelContext.insert(newChat)
            selectedChat = newChat
        }
    }

    func createChatWithMessage(_ messageText: String) {
        // Create new chat with selected model
        let newChat = Chat(modelId: settings.defaultModelId)
        modelContext.insert(newChat)

        // Add user message
        let userMessage = Message(content: messageText, isFromUser: true, chat: newChat)
        newChat.messages.append(userMessage)
        modelContext.insert(userMessage)

        // Update chat title with first message
        let title = String(messageText.prefix(50))
        newChat.title = title

        // Select the new chat - streaming will start in ChatDetailView
        withAnimation {
            selectedChat = newChat
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedChat: Chat?

    @State private var messageText: String = ""
    @State private var errorMessage: String?
    @State private var showSettingsAlert: Bool = false
    @Environment(SettingsManager.self) private var settings
    @FocusState private var isInputFocused: Bool
    @State private var availableModels: [OpenRouterModel] = []
    @State private var isLoadingModels = false
    @State private var selectedModelId: String = ""

    var enabledAvailableModels: [OpenRouterModel] {
        availableModels.filter { settings.enabledModels.contains($0.id) }
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "message")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Start a new conversation", comment: "Empty state title")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Spacer()

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

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $messageText)
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
                            if press.key == .return {
                                if press.modifiers.contains(.shift) {
                                    return .ignored
                                }
                                // No shift, send message if not empty
                                if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sendMessage()
                                }
                                return .handled
                            }
                            return .ignored
                        }

                    if messageText.isEmpty {
                        Text("Enter your message", comment: "Input placeholder")
                            .font(settings.customFont)
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                } else if !enabledAvailableModels.isEmpty {
                    Picker("", selection: $selectedModelId) {
                        ForEach(enabledAvailableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }

            // Load available models and set default
            selectedModelId = settings.defaultModelId
            Task {
                await loadModels()
            }
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Check API key
        if !settings.hasApiKey {
            showSettingsAlert = true
            return
        }

        // Create new chat with selected model
        let newChat = Chat(modelId: selectedModelId)
        modelContext.insert(newChat)

        // Add user message
        let userMessage = Message(content: messageText, isFromUser: true, chat: newChat)
        newChat.messages.append(userMessage)
        modelContext.insert(userMessage)

        // Update chat title with first message
        let title = String(messageText.prefix(50))
        newChat.title = title

        messageText = ""
        errorMessage = nil

        // Select the new chat immediately - streaming will start in ChatDetailView
        selectedChat = newChat
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
}

#Preview {
    ContentView()
        .modelContainer(for: Chat.self, inMemory: true)
}
