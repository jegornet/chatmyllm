//
//  QuickChatWindow.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 21. 3. 2026.
//

import SwiftUI

struct QuickChatWindow: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @Environment(SettingsManager.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            // Input area
            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(settings.customFont)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                        )
                        .focused($isFocused)
                        .onKeyPress { press in
                            if press.key == .return {
                                if press.modifiers.contains(.shift) {
                                    return .ignored
                                }
                                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    onSubmit(text)
                                }
                                return .handled
                            } else if press.key == .escape {
                                onCancel()
                                return .handled
                            }
                            return .ignored
                        }

                    if text.isEmpty {
                        Text("Type your message and press Enter...", comment: "Quick chat placeholder")
                            .font(settings.customFont)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 70)

                HStack {
                    Text("⏎ Send  •  ⇧⏎ New line  •  Esc Cancel", comment: "Quick chat shortcuts hint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
        }
        .frame(width: 800, height: 110)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

#Preview {
    QuickChatWindow(
        text: .constant(""),
        onSubmit: { _ in },
        onCancel: {}
    )
    .environment(SettingsManager.shared)
}
