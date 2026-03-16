//
//  OpenRouterModels.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import Foundation

struct OpenRouterModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let pricing: ModelPricing?
    let contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case pricing
        case contextLength = "context_length"
    }
}

struct ModelPricing: Codable, Hashable {
    let prompt: String?
    let completion: String?
}

struct ModelsResponse: Codable {
    let data: [OpenRouterModel]
}
