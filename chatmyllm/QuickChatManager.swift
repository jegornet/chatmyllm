//
//  QuickChatManager.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 21. 3. 2026.
//

import SwiftUI
import SwiftData

extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let createQuickChat = Notification.Name("createQuickChat")
    static let quickChatHotKeyPressed = Notification.Name("quickChatHotKeyPressed")
}

@Observable
class QuickChatManager {
    static let shared = QuickChatManager()

    private var quickChatWindow: NSWindow?
    private var quickChatText: String = ""

    private init() {}

    func toggleQuickChat() {
        if let window = quickChatWindow, window.isVisible {
            hideQuickChat()
        } else {
            showQuickChat()
        }
    }

    func showQuickChat() {
        if let window = quickChatWindow {
            quickChatText = ""
            window.orderFront(nil)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 180),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()

        let hostingView = NSHostingView(
            rootView: QuickChatWindow(
                text: Binding(
                    get: { self.quickChatText },
                    set: { self.quickChatText = $0 }
                ),
                onSubmit: { [weak self] text in
                    self?.handleSubmit(text)
                },
                onCancel: { [weak self] in
                    self?.hideQuickChat()
                }
            )
            .environment(SettingsManager.shared)
        )

        window.contentView = hostingView
        window.orderFront(nil)
        window.makeKey()

        quickChatWindow = window
    }

    func hideQuickChat() {
        quickChatWindow?.close()
        quickChatWindow = nil
        quickChatText = ""
    }

    private func handleSubmit(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        hideQuickChat()

        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        // Find main window (including hidden ones)
        let mainWindow = NSApp.windows.first { window in
            !(window is NSPanel) &&
            !window.title.localizedCaseInsensitiveContains("settings")
        }

        // Show main window if hidden, or bring to front if visible
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }

        // Create chat after window is shown
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .createQuickChat,
                object: nil,
                userInfo: ["messageText": trimmedText]
            )
        }
    }
}
