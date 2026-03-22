//
//  ChatListView.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import SwiftUI
import SwiftData

struct ChatListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Chat.createdAt, order: .reverse) private var chats: [Chat]
    @Binding var selectedChat: Chat?

    @Environment(SettingsManager.self) private var settings
    @FocusedValue(\.newChatAction) private var newChatAction

    @State private var isSelectionMode = false
    @State private var selectedChatsForAction: Set<UUID> = []

    var body: some View {
        List(selection: $selectedChat) {
                ForEach(chats) { chat in
                    Group {
                        if isSelectionMode {
                            chatRowContent(for: chat)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleSelection(for: chat)
                                }
                        } else {
                            NavigationLink(value: chat) {
                                chatRowContent(for: chat)
                            }
                        }
                    }
                .contextMenu {
                    if isSelectionMode {
                        Button {
                            exitSelectionMode()
                        } label: {
                            Label(String(localized: "Exit Selection Mode", comment: "Exit selection mode context menu"), systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button {
                            enterSelectionMode(for: chat)
                        } label: {
                            Label(String(localized: "Select", comment: "Select context menu"), systemImage: "checkmark.circle")
                        }

                        Divider()

                        Button {
                            renameChat(chat)
                        } label: {
                            Label(String(localized: "Rename", comment: "Rename context menu"), systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteChat(chat)
                        } label: {
                            Label(String(localized: "Delete", comment: "Delete context menu"), systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete(perform: deleteChats)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectAllChats()
                    } label: {
                        Label("Select All", systemImage: "checklist")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        deleteSelectedChats()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedChatsForAction.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exitSelectionMode()
                    } label: {
                        Label("Exit", systemImage: "arrow.uturn.backward")
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNewChat) {
                        Label(String(localized: "New Chat", comment: "New chat button"), systemImage: "plus")
                    }
                    .disabled(newChatAction?.canCreate == false)
                }
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

    private func deleteChats(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let chatToDelete = chats[index]
                if selectedChat?.id == chatToDelete.id {
                    selectedChat = nil
                }
                modelContext.delete(chatToDelete)
            }
        }
    }

    private func deleteChat(_ chat: Chat) {
        withAnimation {
            if selectedChat?.id == chat.id {
                selectedChat = nil
            }
            modelContext.delete(chat)
        }
    }

    private func renameChat(_ chat: Chat) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Chat", comment: "Rename alert title")
        alert.informativeText = String(localized: "Enter new name:", comment: "Rename alert message")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = chat.title
        alert.accessoryView = textField

        alert.addButton(withTitle: String(localized: "OK", comment: "OK button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Cancel button"))

        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTitle.isEmpty {
                chat.title = newTitle
            }
        }
    }

    private func enterSelectionMode(for chat: Chat) {
        withAnimation {
            isSelectionMode = true
            selectedChatsForAction = [chat.id]
        }
    }

    private func toggleSelection(for chat: Chat) {
        if selectedChatsForAction.contains(chat.id) {
            selectedChatsForAction.remove(chat.id)
        } else {
            selectedChatsForAction.insert(chat.id)
        }
    }

    private func exitSelectionMode() {
        withAnimation {
            isSelectionMode = false
            selectedChatsForAction.removeAll()
        }
    }

    private func selectAllChats() {
        selectedChatsForAction = Set(chats.map { $0.id })
    }

    private func deleteSelectedChats() {
        withAnimation {
            for chat in chats {
                if selectedChatsForAction.contains(chat.id) {
                    if selectedChat?.id == chat.id {
                        selectedChat = nil
                    }
                    modelContext.delete(chat)
                }
            }
            selectedChatsForAction.removeAll()
            isSelectionMode = false
        }
    }

    @ViewBuilder
    private func chatRowContent(for chat: Chat) -> some View {
        HStack(spacing: 8) {
            if isSelectionMode {
                Button {
                    toggleSelection(for: chat)
                } label: {
                    Image(systemName: selectedChatsForAction.contains(chat.id) ? "checkmark.square.fill" : "square")
                        .foregroundColor(selectedChatsForAction.contains(chat.id) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(settings.customFont)
                    .lineSpacing(settings.lineSpacing)
                    .lineLimit(1)

                Text(chat.createdAt, format: .dateTime)
                    .font(.custom(settings.fontName, size: settings.fontSize * 0.7))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedChat?.id != chat.id {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
