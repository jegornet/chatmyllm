//
//  OpenRouterService.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import Foundation

struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

struct OpenRouterRequest: Codable {
    let model: String
    let messages: [OpenRouterMessage]
}

struct OpenRouterChoice: Codable {
    let message: OpenRouterMessage
}

struct OpenRouterResponse: Codable {
    let choices: [OpenRouterChoice]
}

enum OpenRouterError: Error, LocalizedError {
    case noApiKey
    case invalidResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return String(localized: "OpenRouter API key not set", comment: "Error: no API key")
        case .invalidResponse:
            return String(localized: "Invalid response received", comment: "Error: invalid response")
        case .networkError(let message):
            return String(localized: "Network error: \(message)", comment: "Error: network error")
        }
    }
}

class OpenRouterService {
    static let shared = OpenRouterService()
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    private let modelsURL = "https://openrouter.ai/api/v1/models"

    private init() {}

    func sendMessage(messages: [Message], model: String = "anthropic/claude-3.5-sonnet") async throws -> String {
        guard !SettingsManager.shared.apiKey.isEmpty else {
            throw OpenRouterError.noApiKey
        }

        let openRouterMessages = messages.map { message in
            OpenRouterMessage(
                role: message.isFromUser ? "user" : "assistant",
                content: message.content
            )
        }

        let request = OpenRouterRequest(
            model: model,
            messages: openRouterMessages
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(SettingsManager.shared.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw OpenRouterError.networkError("Error encoding request")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        do {
            let openRouterResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            guard let firstChoice = openRouterResponse.choices.first else {
                throw OpenRouterError.invalidResponse
            }
            return firstChoice.message.content
        } catch {
            throw OpenRouterError.networkError("Error decoding response: \(error.localizedDescription)")
        }
    }

    func fetchModels() async throws -> [OpenRouterModel] {
        guard let url = URL(string: modelsURL) else {
            throw OpenRouterError.networkError("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        do {
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return modelsResponse.data
        } catch {
            throw OpenRouterError.networkError("Failed to decode models: \(error.localizedDescription)")
        }
    }
}
