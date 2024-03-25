//
//  texture.swift
//  ycmapper
//
//  Created by Alexander Orlov on 25.11.2023.
//

import Foundation

extension BitmapRenderer {
    class Texture {
        let uuid: UUID
        let frame: Cache.Sprite.Animation.Frame
        
        var origin: CGPoint
        var indexes: yc_vid_indexes_t
        var grid: size_t
        var order: yc_vid_texture_order_t
        var visibility: yc_vid_texture_visibility_t
        
        init(
            uuid: UUID,
            frame: Cache.Sprite.Animation.Frame,
            origin: CGPoint,
            indexes: yc_vid_indexes_t, 
            grid: size_t,
            order: yc_vid_texture_order_t,
            visibility: yc_vid_texture_visibility_t
        ) {
            self.uuid = uuid
            self.frame = frame
            self.origin = origin
            self.indexes = indexes
            self.grid = grid
            self.order = order
            self.visibility = visibility
        }
    }
}
