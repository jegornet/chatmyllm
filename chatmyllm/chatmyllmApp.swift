//
//  chatmyllmApp.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026..
//

import SwiftUI
import SwiftData

struct NewChatAction {
    let action: () -> Void
    let canCreate: Bool
}

struct NewChatFocusedValueKey: FocusedValueKey {
    typealias Value = NewChatAction
}

extension FocusedValues {
    var newChatAction: NewChatFocusedValueKey.Value? {
        get { self[NewChatFocusedValueKey.self] }
        set { self[NewChatFocusedValueKey.self] = newValue }
    }
}

@main
struct chatmyllmApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Chat.self,
            Message.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @FocusedValue(\.newChatAction) private var newChatAction
    @State private var settings = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .onAppear {
                    // Show settings if no API key is set
                    if !SettingsManager.shared.hasApiKey {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            openSettings()
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Chat", comment: "New chat menu item")) {
                    newChatAction?.action()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newChatAction == nil || newChatAction?.canCreate == false)
            }
        }

        Settings {
            SettingsView(settings: settings)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
