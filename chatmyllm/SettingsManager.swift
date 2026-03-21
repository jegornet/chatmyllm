//
//  SettingsManager.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import Foundation
import SwiftUI

@Observable
class SettingsManager {
    static let shared = SettingsManager()

    private let apiKeyKey = "openrouter_api_key"
    private let fontNameKey = "app_font_name"
    private let fontSizeKey = "app_font_size"
    private let lineSpacingKey = "app_line_spacing"
    private let enabledModelsKey = "enabled_models"
    private let defaultModelIdKey = "default_model_id"
    private let quickChatEnabledKey = "quick_chat_enabled"

    var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
        }
    }

    var hasApiKey: Bool {
        !apiKey.isEmpty
    }

    var fontName: String {
        didSet {
            UserDefaults.standard.set(fontName, forKey: fontNameKey)
        }
    }

    var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: fontSizeKey)
        }
    }

    var lineSpacing: CGFloat {
        didSet {
            UserDefaults.standard.set(lineSpacing, forKey: lineSpacingKey)
        }
    }

    var customFont: Font {
        .custom(fontName, size: fontSize)
    }

    var customNSFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    var enabledModels: Set<String> {
        didSet {
            if let data = try? JSONEncoder().encode(enabledModels) {
                UserDefaults.standard.set(data, forKey: enabledModelsKey)
            }
        }
    }

    var defaultModelId: String {
        didSet {
            UserDefaults.standard.set(defaultModelId, forKey: defaultModelIdKey)
        }
    }

    var quickChatEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quickChatEnabled, forKey: quickChatEnabledKey)
        }
    }

    private init() {
        // Load values from UserDefaults
        self.apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        self.fontName = UserDefaults.standard.string(forKey: fontNameKey) ?? "SF Pro"
        let size = UserDefaults.standard.double(forKey: fontSizeKey)
        self.fontSize = size > 0 ? size : 14.0
        let spacing = UserDefaults.standard.double(forKey: lineSpacingKey)
        self.lineSpacing = spacing > 0 ? spacing : 2.0

        if let data = UserDefaults.standard.data(forKey: enabledModelsKey),
           let models = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.enabledModels = models
        } else {
            self.enabledModels = ["anthropic/claude-3.5-sonnet"]
        }

        self.defaultModelId = UserDefaults.standard.string(forKey: defaultModelIdKey) ?? "anthropic/claude-3.5-sonnet"
        self.quickChatEnabled = UserDefaults.standard.bool(forKey: quickChatEnabledKey)
    }
}
