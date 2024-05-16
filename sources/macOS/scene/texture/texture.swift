//
//  texture.swift
//  ycmapper
//
//  Created by Alexander Orlov on 25.11.2023.
//

import Foundation
import SpriteKit

extension MapScene {
    class Texture: Equatable {
        static func == (lhs: MapScene.Texture, rhs: MapScene.Texture) -> Bool {
            lhs.uuid == rhs.uuid &&
            lhs.frame.shift == rhs.frame.shift &&
            lhs.node == rhs.node &&
            lhs.indexes.x == rhs.indexes.x &&
            lhs.indexes.y == rhs.indexes.y &&
            lhs.grid == rhs.grid &&
            lhs.order?.rawValue == rhs.order?.rawValue &&
            lhs.visibility.rawValue == rhs.visibility.rawValue &&
            lhs.isEnabled == rhs.isEnabled
        }
        
        let uuid: UUID
        let frame: Cache.Sprite.Animation.Frame
        let node: SKSpriteNode
        
        var indexes: yc_vid_indexes_t
        var grid: size_t
        var order: yc_vid_texture_order_t?
        var visibility: yc_vid_texture_visibility_t { didSet { self.update() } }
        var isEnabled: Bool = true { didSet { self.update() } }

        init(
            uuid: UUID,
            frame: Cache.Sprite.Animation.Frame,
            indexes: yc_vid_indexes_t, 
            grid: size_t,
            order: yc_vid_texture_order_t?,
            visibility: yc_vid_texture_visibility_t
        ) {
            self.uuid = uuid
            self.frame = frame
            
            self.node = .init(texture: frame.texture, size: frame.texture.size())
            self.node.anchorPoint = .init(x: 0.0, y: 0.0)
            
            self.indexes = indexes
            self.grid = grid
            self.order = order
            self.visibility = visibility
        }
        
        func update() {
            self.node.isHidden = self.visibility == YC_VID_TEXTURE_VISIBILITY_OFF || !self.isEnabled
        }
    }
}
