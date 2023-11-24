//
//  renderer.swift
//  ycmapper
//
//  Created by Alexander Orlov on 23.11.2023.
//

import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import Combine

public class BitmapRenderer: ObservableObject {
    public let callbacks: yc_vid_texture_api_t
    private let fetcher: Fetcher
    
    @Published
    private(set) public var canvas: NSImage? = nil
    
    
    private var sprites: [UInt32 : Sprite] = .init()
    private class Sprite {
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
                
                deinit {
                    debugPrint("deinit FRAME")
                }
                
                init(size: CGSize, shift: CGPoint, image: CGImage?) {
                    self.size = size
                    self.shift = shift
                    self.image = image!
                }
            }
            
            deinit {
                debugPrint("deinit ANIMATION")
            }
            
            init(fps: UInt16, keyframe_idx: UInt16, frames: [Frame]) {
                self.fps = fps
                self.keyframe_idx = keyframe_idx
                self.frames = frames
            }
        }
        
        deinit {
            debugPrint("deinit SPRITE")
        }
        
        init(id: UInt32, idx: UInt16, type: yc_res_pro_object_type_t, indexes: [[Animation].Index], animations: [Animation]) {
            self.id = id
            self.idx = idx
            self.type = type
            self.indexes = indexes
            self.animations = animations
        }
    }
    
    private var textures: [UUID : Texture] = .init()
    private class Texture {
        let uuid: UUID
        let frame: Sprite.Animation.Frame
        
        var origin: CGPoint
        var order: yc_vid_texture_order_t
        var visibility: yc_vid_texture_visibility_t
        
        deinit {
            debugPrint("deinit TEXTURE")
        }
        
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
    
    private var ctx = CGContext(
        data: nil, width: 8000, height: 3600,
        bitsPerComponent: 8, bytesPerRow: 4 * 8000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    
    deinit {
        debugPrint("deinit RENDERER")
    }
    
    public init(fetcher: Fetcher) {
        self.fetcher = fetcher
        self.callbacks = yc_vid_texture_api_t { type, sprite_idx, orientation, destination, ctx  in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee.initialize(
                type: type, sprite_idx: sprite_idx, orientation: orientation, destination: destination
            ) ?? YC_VID_STATUS_CORRUPTED
        } invalidate: { texture, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .invalidate(texture: texture) ?? YC_VID_STATUS_CORRUPTED
        } is_equal: { lhs, rhs in
            lhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
            ==
            rhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        } set_visibility: { texture, visibility, order, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .update(texture: texture, visibility: visibility, order: order) ?? YC_VID_STATUS_CORRUPTED
        } set_coordinates: { texture, coordinates, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .update(texture: texture, coordinates: coordinates) ?? YC_VID_STATUS_CORRUPTED
        }
    }
}

// MARK: - Usage

public extension BitmapRenderer {
    func render() {
        guard let ctx = self.ctx else { return }
        
        for (_, texture) in self.textures.sorted(by: { $0.value.order.rawValue < $1.value.order.rawValue }) {
            guard texture.visibility == YC_VID_TEXTURE_VISIBILITY_ON else { continue }
            
            ctx.draw(
                texture.frame.image,
                in: .init( // CG coords are upside down
                    origin: .init(
                        x: texture.origin.x + texture.frame.shift.x,
                        y: CGFloat(ctx.height) - texture.origin.y + texture.frame.shift.y
                    ),
                    size: .init(width: texture.frame.size.width, height: texture.frame.size.height)
                )
            )
        }
        
        let frame = ctx.makeImage()!
        
        DispatchQueue.main.async(execute: {
            self.canvas = .init(
                cgImage: frame,
                size: .init(width: ctx.width, height: ctx.height)
            )
        })
    }
    
    func invalidate(fully: Bool = false) {
        if fully { self.canvas = nil }
        
        self.ctx = nil
        self.sprites.removeAll()
        self.textures.removeAll()
    }
}

// MARK: - Platform API

private extension BitmapRenderer {
    func initialize(
        type: yc_res_pro_object_type_t,
        sprite_idx: UInt16,
        orientation: yc_res_math_orientation_t,
        destination: UnsafeMutablePointer<yc_vid_texture_set_t>?
    ) -> yc_vid_status_t {
        guard let destination = destination else { return YC_VID_STATUS_INPUT }
        
        let fid = yc_res_pro_fid_from(sprite_idx, type)
        let type_a = yc_res_pro_object_type_from_fid(fid)
        let sprite_idx_a = yc_res_pro_index_from_sprite_id(fid)
        
        assert(type_a == type && sprite_idx_a == sprite_idx)
        
        guard let sprite = self.sprites[fid] else {
            // TODO: Find proper palette!
            var palette = yc_res_pal_parse_result_t()
            let status = yc_res_pal_parse(
                self.fetcher.root.appending(path: "COLOR.PAL").path,
                withUnsafePointer(to: io_fs_api, { $0 }),
                &palette
            )
            
            assert(YC_RES_PAL_STATUS_OK == status)
            defer { palette.colors.deallocate() }
            
            let parsed = self.fetcher.sprite(at: sprite_idx, for: type)
            defer { yc_res_frm_sprite_invalidate(parsed.sprite); parsed.sprite.deallocate() }
            
            let animations: [Sprite.Animation] = Array(
                UnsafeBufferPointer(
                    start: parsed.sprite.pointee.animations,
                    count: parsed.sprite.pointee.count
                )
            ).map({ animation in
                let frames: [Sprite.Animation.Frame] = Array(
                    UnsafeBufferPointer(start: animation.frames, count: animation.count)
                ).map({ texture in
                    let ref = CGContext(
                        data: nil,
                        width: Int(texture.dimensions.horizontal),
                        height: Int(texture.dimensions.vertical),
                        bitsPerComponent: 8, // UInt8
                        bytesPerRow: Int(texture.dimensions.horizontal) * 4, // count(RGBA) == 4
                        space: .init(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )!
                    
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
                    
                    return .init(
                        size: .init(
                            width: CGFloat(texture.dimensions.horizontal),
                            height: CGFloat(texture.dimensions.vertical)
                        ),
                        shift: .init(
                            x: CGFloat(texture.shift.horizontal + animation.shift.horizontal),
                            y: CGFloat(texture.shift.vertical + animation.shift.vertical)
                        ),
                        image: ref.makeImage()!
                    )
                })
                
                return .init(fps: animation.fps, keyframe_idx: animation.keyframe_idx, frames: frames)
            })
            
            let sprite: Sprite = .init(
                id: fid,
                idx: sprite_idx,
                type: type,
                indexes: [
                    parsed.sprite.pointee.orientations.0,
                    parsed.sprite.pointee.orientations.1,
                    parsed.sprite.pointee.orientations.2,
                    parsed.sprite.pointee.orientations.3,
                    parsed.sprite.pointee.orientations.4,
                    parsed.sprite.pointee.orientations.5,
                ],
                animations: animations
            )
            
            self.sprites[fid] = sprite
            
            return self.initialize(type: type, sprite_idx: sprite_idx, orientation: orientation, destination: destination)
        }
        
        let animation = sprite.animations[sprite.indexes[Int(orientation.rawValue)]]
        
        destination.pointee.fps = animation.fps
        destination.pointee.keyframe_idx = animation.keyframe_idx
        
        destination.pointee.count = animation.frames.count
        destination.pointee.textures = .allocate(capacity: animation.frames.count) // will freed by the view
        
        for (index, frame) in animation.frames.enumerated() {
            let texture: Texture = .init(
                uuid: .init(),
                frame: frame,
                origin: .zero,
                order: YC_VID_TEXTURE_ORDER_NORMAL,
                visibility: YC_VID_TEXTURE_VISIBILITY_OFF
            )
            
            self.textures[texture.uuid] = texture
            
            destination.pointee.textures.advanced(by: index).pointee.handle = .allocate(
                byteCount: MemoryLayout<UUID>.size,
                alignment: 0
            )
            
            destination.pointee.textures.advanced(by: index).pointee.handle.copyMemory(
                from: withUnsafePointer(to: texture.uuid, { $0 }),
                byteCount: MemoryLayout<UUID>.size
            )
        }
        
        return YC_VID_STATUS_OK
    }
    
    func invalidate(texture: UnsafeMutablePointer<yc_vid_texture_t>?) -> yc_vid_status_t {
        guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        else { return YC_VID_STATUS_INPUT }
        
        // freeing what allocated in init ^^^
        texture?.pointee.handle.deallocate()
        texture?.pointee.handle = nil
        
        self.textures.removeValue(forKey: uuid)
        
        return YC_VID_STATUS_OK
    }
}

// MARK: - Updates

private extension BitmapRenderer {
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        visibility: yc_vid_texture_visibility_t,
        order: yc_vid_texture_order_t
    ) -> yc_vid_status_t {
        guard let texture = texture else { return YC_VID_STATUS_INPUT }
        
        let uuid = texture.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        guard self.textures[uuid] != nil else { return YC_VID_STATUS_CORRUPTED }
        
        self.textures[uuid]!.order = order
        self.textures[uuid]!.visibility = visibility
        
        return YC_VID_STATUS_OK
    }
    
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        coordinates: yc_vid_coordinates_t
    ) -> yc_vid_status_t {
        guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        else { return YC_VID_STATUS_INPUT }
        
        guard self.textures[uuid] != nil
        else { return YC_VID_STATUS_CORRUPTED }
        
        self.textures[uuid]?.origin.x = CGFloat(coordinates.x)
        self.textures[uuid]?.origin.y = CGFloat(coordinates.y)
        
        return YC_VID_STATUS_OK
    }
}
