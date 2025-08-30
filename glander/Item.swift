//
//  Item.swift
//  glander
//
//  Created by 符镇岳 on 2025/8/30.
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
