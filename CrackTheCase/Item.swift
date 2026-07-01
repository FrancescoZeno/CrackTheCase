//
//  Item.swift
//  CrackTheCase
//
//  Created by AFP PAR 049 on 01/07/2026.
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
