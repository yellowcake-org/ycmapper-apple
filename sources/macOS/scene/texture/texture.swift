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
            lhs.uuid == rhs.uuid
        }
        
        let uuid: UUID
        let node: SKSpriteNode
        
        var grid: size_t
        var order: yc_vid_texture_order_t?
        var indexes: yc_vid_indexes_t
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
            
            self.node = .init(texture: frame.texture, size: frame.texture.size())
            self.node.anchorPoint = .init(
                x: frame.shift.x / frame.texture.size().width,
                y: frame.shift.y / frame.texture.size().height
            )
            
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
