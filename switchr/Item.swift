//
//  Item.swift
//  switchr
//
//  Created by James Officer on 9/7/2026.
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
