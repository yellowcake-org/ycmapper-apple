//
//  sprite.swift
//  ycmapper
//
//  Created by Alexander Orlov on 25.11.2023.
//

import Foundation
import CoreGraphics

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
                let size: CGSize
                let shift: CGPoint
                
                let image: CGImage
                
                init(size: CGSize, shift: CGPoint, image: CGImage?) {
                    self.size = size
                    self.shift = shift
                    self.image = image!
                }
                
                convenience
                init(raw texture: yc_res_frm_texture_t, shift: yc_res_frm_shift_t, palette: yc_res_pal_parse_result_t) {
                    let ref = CGContext(
                        data: nil,
                        width: Int(texture.dimensions.horizontal),
                        height: Int(texture.dimensions.vertical),
                        bitsPerComponent: 8, // UInt8
                        bytesPerRow: Int(texture.dimensions.horizontal) * 4, // count(RGBA) == 4
                        space: .init(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )!
                    
                    ref.interpolationQuality = .none
                    
                    for v_idx in 0..<Int(texture.dimensions.vertical) {
                        for h_idx in 0..<Int(texture.dimensions.horizontal) {
                            let rows = v_idx * (Int(texture.dimensions.horizontal) * 4)
                            
                            let color_idx = texture.pixels.advanced(by: h_idx + v_idx * Int(texture.dimensions.horizontal)).pointee
                            var color = palette.colors.advanced(by: Int(color_idx)).pointee
                            let color_is_transparent = yc_res_pal_color_is_transparent(&color)

                            ref.data?.assumingMemoryBound(to: UInt8.self)
                                .advanced(by: (h_idx * 4 + 0) + rows).pointee = color.r
                            ref.data?.assumingMemoryBound(to: UInt8.self)
                                .advanced(by: (h_idx * 4 + 1) + rows).pointee = color.g
                            ref.data?.assumingMemoryBound(to: UInt8.self)
                                .advanced(by: (h_idx * 4 + 2) + rows).pointee = color.b
                            ref.data?.assumingMemoryBound(to: UInt8.self)
                                .advanced(by: (h_idx * 4 + 3) + rows).pointee = color_is_transparent ? .min : .max
                        }
                    }
                    
                    self.init(
                        size: .init(
                            width: CGFloat(texture.dimensions.horizontal),
                            height: CGFloat(texture.dimensions.vertical)
                        ),
                        shift: .init(
                            x: CGFloat(
                                shift.horizontal + texture.shift.horizontal - Int16(texture.dimensions.horizontal) / 2
                            ),
                            y: CGFloat(
                                shift.vertical + texture.shift.vertical
                            )
                        ),
                        image: ref.makeImage()!
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
