//
//  Item.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026..
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
