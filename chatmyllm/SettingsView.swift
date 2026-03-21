//
//  SettingsView.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: SettingsManager

    @State private var availableModels: [OpenRouterModel] = []
    @State private var isLoadingModels = false
    @State private var modelSearchText: String = ""

    let availableFonts = [
        "SF Pro",
        "Helvetica Neue",
        "Menlo",
        "Monaco",
        "Courier New",
        "Arial",
        "Times New Roman",
        "Georgia"
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                // General Tab
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                // Models Tab
                modelsTab
                    .tabItem {
                        Label("Models", systemImage: "cpu")
                    }
            }
            .padding()

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Cancel button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save", comment: "Save button")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(settings.enabledModels.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    var generalTab: some View {
        Form {
            Section(String(localized: "OpenRouter API", comment: "API section title")) {
                SecureField(String(localized: "Enter API key", comment: "API key field placeholder"), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)

                Text("Get API key at openrouter.ai", comment: "API key help text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(String(localized: "Quick Chat", comment: "Quick chat section title")) {
                Toggle(String(localized: "Open quick chat window on ⌥Space", comment: "Quick chat toggle label"), isOn: $settings.quickChatEnabled)

                Text("Press Option+Space anywhere to open a quick chat window", comment: "Quick chat help text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(String(localized: "Interface Font", comment: "Font section title")) {
                Picker(String(localized: "Font", comment: "Font picker label"), selection: $settings.fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Size", comment: "Font size label")
                    Slider(value: $settings.fontSize, in: 10...20, step: 1)
                    Text("\(Int(settings.fontSize))")
                        .frame(width: 30)
                }

                HStack {
                    Text("Line spacing", comment: "Line spacing label")
                    Slider(value: $settings.lineSpacing, in: 0...10, step: 0.5)
                    Text("\(settings.lineSpacing, specifier: "%.1f")")
                        .frame(width: 30)
                }

                Text("Example: This is text with selected font", comment: "Font preview text")
                    .font(.custom(settings.fontName, size: settings.fontSize))
                    .lineSpacing(settings.lineSpacing)
                    .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    var filteredModels: [OpenRouterModel] {
        let filtered: [OpenRouterModel]
        if modelSearchText.isEmpty {
            filtered = availableModels
        } else {
            filtered = availableModels.filter { model in
                model.name.localizedCaseInsensitiveContains(modelSearchText) ||
                (model.description?.localizedCaseInsensitiveContains(modelSearchText) ?? false)
            }
        }
        return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var enabledAvailableModels: [OpenRouterModel] {
        availableModels.filter { settings.enabledModels.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var modelsTab: some View {
        VStack(spacing: 0) {
            if isLoadingModels {
                ProgressView(String(localized: "Loading models...", comment: "Loading models text"))
                    .padding()
            } else if availableModels.isEmpty {
                VStack(spacing: 12) {
                    Text("No models loaded", comment: "No models text")
                        .foregroundColor(.secondary)
                    Button(String(localized: "Load Models", comment: "Load models button")) {
                        Task {
                            await loadModels()
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(String(localized: "Search models...", comment: "Model search placeholder"), text: $modelSearchText)
                            .textFieldStyle(.plain)
                        if !modelSearchText.isEmpty {
                            Button(action: { modelSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Models list
                    List {
                        ForEach(filteredModels) { model in
                            Toggle(isOn: Binding(
                                get: { settings.enabledModels.contains(model.id) },
                                set: { isEnabled in
                                    if isEnabled {
                                        settings.enabledModels.insert(model.id)
                                        // Set as default if it's the first enabled model
                                        if settings.enabledModels.count == 1 {
                                            settings.defaultModelId = model.id
                                        }
                                    } else {
                                        settings.enabledModels.remove(model.id)
                                        // If we disabled the default model, pick another one
                                        if settings.defaultModelId == model.id {
                                            settings.defaultModelId = enabledAvailableModels.first?.id ?? "anthropic/claude-3.5-sonnet"
                                        }
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.body)
                                    if let description = model.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }

                    // Default model picker
                    if !settings.enabledModels.isEmpty {
                        Divider()
                            .padding(.top, 8)

                        HStack {
                            Text("Default model for new chats:", comment: "Default model label")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Picker("", selection: $settings.defaultModelId) {
                                ForEach(enabledAvailableModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear {
            if availableModels.isEmpty {
                Task {
                    await loadModels()
                }
            }
        }
    }

    private func loadModels() async {
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
    SettingsView(settings: SettingsManager.shared)
}
