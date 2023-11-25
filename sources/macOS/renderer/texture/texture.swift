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
        let frame: Sprite.Animation.Frame
        
        var origin: CGPoint
        var order: yc_vid_texture_order_t
        var visibility: yc_vid_texture_visibility_t
        
        deinit { debugPrint("deinit TEXTURE") }
        
        init(
            uuid: UUID, frame: Sprite.Animation.Frame, origin: CGPoint,
            order: yc_vid_texture_order_t, visibility: yc_vid_texture_visibility_t
        ) {
            self.uuid = uuid
            self.frame = frame
            self.origin = origin
            self.order = order
            self.visibility = visibility
        }
    }
}
