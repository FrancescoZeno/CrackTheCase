import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var completionTime: Double
    
    init(timestamp: Date, completionTime: Double) {
        self.timestamp = timestamp
        self.completionTime = completionTime
    }
}
