//
//  sprite.swift
//  ycmapper
//
//  Created by Alexander Orlov on 25.11.2023.
//

import Foundation
import CoreGraphics
import SpriteKit

extension Cache {
    class Sprite {
        let id: UInt32
        
        let idx: UInt16
        let type: yc_res_pro_object_type_t
        
        let indexes: [[Animation].Index]
        let animations: [Animation]
        class Animation {
            let fps, keyframe_idx: UInt16
            let frames: [Frame]
            
            class Frame {
                let shift: CGPoint
                let texture: SKTexture
                
                init(shift: CGPoint, texture: SKTexture) {
                    self.shift = shift
                    self.texture = texture
                    self.texture.filteringMode = .nearest
                }
                
                convenience
                init(raw texture: yc_res_frm_texture_t, shift: yc_res_frm_shift_t, palette: yc_res_pal_parse_result_t) {
                    let count = Int(texture.dimensions.horizontal) * Int(texture.dimensions.vertical) * 4
                    var bytes: [UInt8] = .init(repeating: 0, count: count)
                    
                    for v_idx in 0..<Int(texture.dimensions.vertical) {
                        for h_idx in 0..<Int(texture.dimensions.horizontal) {
                            let rows = v_idx.distance(to: Int(texture.dimensions.vertical - 1)) * (Int(texture.dimensions.horizontal) * 4)
                            
                            let color_idx = texture.pixels.advanced(by: h_idx + v_idx * Int(texture.dimensions.horizontal)).pointee
                            var color = palette.colors.advanced(by: Int(color_idx)).pointee
                            let color_is_transparent = yc_res_pal_color_is_transparent(&color)

                            bytes[(h_idx * 4 + 0) + rows] = color.r
                            bytes[(h_idx * 4 + 1) + rows] = color.g
                            bytes[(h_idx * 4 + 2) + rows] = color.b
                            bytes[(h_idx * 4 + 3) + rows] = color_is_transparent ? .min : .max
                        }
                    }
                    
                    let size: CGSize = .init(
                        width: CGFloat(texture.dimensions.horizontal),
                        height: CGFloat(texture.dimensions.vertical)
                    )
                    
                    self.init(
                        shift: .init(
                            x: CGFloat(shift.horizontal + texture.shift.horizontal - Int16(texture.dimensions.horizontal) / 2),
                            y: CGFloat(shift.vertical + texture.shift.vertical)
                        ),
                        texture: .init(data: .init(bytes: &bytes, count: count), size: size)
                    )
                }
            }
            
            init(fps: UInt16, keyframe_idx: UInt16, frames: [Frame]) {
                self.fps = fps
                self.keyframe_idx = keyframe_idx
                self.frames = frames
            }
            
            convenience init(raw animation: yc_res_frm_animation_t, palette: yc_res_pal_parse_result_t) {
                let frames: [Sprite.Animation.Frame] = Array(
                    UnsafeBufferPointer(start: animation.frames, count: animation.count)
                ).map({ .init(raw: $0, shift: animation.shift, palette: palette) })
                
                self.init(fps: animation.fps, keyframe_idx: animation.keyframe_idx, frames: frames)
            }
        }
        
        init(id: UInt32, idx: UInt16, type: yc_res_pro_object_type_t, indexes: [[Animation].Index], animations: [Animation]) {
            self.id = id
            self.idx = idx
            self.type = type
            self.indexes = indexes
            self.animations = animations
        }
    }
}
