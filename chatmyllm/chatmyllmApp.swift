//
//  chatmyllmApp.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026..
//

import SwiftUI
import SwiftData
import AppKit

// App delegate to handle window closing behavior
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let frameKey = "MainWindowFrame"

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure all windows immediately
        for window in NSApplication.shared.windows {
            configureWindow(window)
        }

        // Watch for new windows as they are created
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                self?.configureWindow(window)
            }
        }

        // Override Cmd-W to hide window instead of closing
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                if let keyWindow = NSApplication.shared.keyWindow {
                    self.saveWindowFrame(keyWindow)
                    keyWindow.orderOut(nil)
                }
                return nil // Consume the event
            }
            return event
        }
    }

    func configureMainWindow() {
        // Set up main window to preserve frame
        for window in NSApplication.shared.windows {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Skip panels (like Quick Chat)
        guard !(window is NSPanel) else { return }

        // Skip settings and other non-main windows
        guard window.title.isEmpty || window.title == "chatmyllm" else { return }

        // Skip if already configured
        guard window.delegate !== self else { return }

        // Set delegate
        window.delegate = self

        // Restore saved frame immediately
        restoreWindowFrame(window)
    }

    private func saveWindowFrame(_ window: NSWindow) {
        let frame = window.frame
        let frameString = NSStringFromRect(frame)
        UserDefaults.standard.set(frameString, forKey: frameKey)
    }

    private func restoreWindowFrame(_ window: NSWindow) {
        guard let frameString = UserDefaults.standard.string(forKey: frameKey) else {
            // No saved frame - let SwiftUI defaultSize handle it
            return
        }

        let frame = NSRectFromString(frameString)

        // Ensure the frame is valid and visible on screen
        if frame.width > 0 && frame.height > 0 {
            window.setFrame(frame, display: false, animate: false)
        }
    }

    // Intercept window close button to hide instead of close
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Save frame before hiding
        saveWindowFrame(sender)
        sender.orderOut(nil) // Hide the window
        return false // Prevent actual closing
    }

    // Called when window will move or resize
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            saveWindowFrame(window)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            saveWindowFrame(window)
        }
    }
}

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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                    // Set up quick chat hotkey on first appear
                    setupQuickChatHotKey()

                    // Show settings if no API key is set
                    if !SettingsManager.shared.hasApiKey {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            openSettings()
                        }
                    }
                }
                .onChange(of: settings.quickChatEnabled) { _, newValue in
                    if newValue {
                        setupQuickChatHotKey()
                    } else {
                        HotKeyManager.shared.unregister()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
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

    private func setupQuickChatHotKey() {
        guard settings.quickChatEnabled else { return }
        HotKeyManager.shared.register()
    }
}
