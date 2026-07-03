//
//  Item.swift
//  lightCoopGame
//
//  Created by AFP PAR 068 on 29/06/2026.
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
