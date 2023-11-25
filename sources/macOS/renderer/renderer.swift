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

class BitmapRenderer: ObservableObject {
    public let callbacks: yc_vid_texture_api_t
    public let cache: Cache
    
    @Published
    private(set) public var canvas: NSImage? = nil
    private var textures: [UUID : Texture] = .init()
    
    private var ctx = CGContext(
        data: nil, width: 8000, height: 3600, 
        bitsPerComponent: 8, bytesPerRow: 4 * 8000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    
    deinit {
        debugPrint("deinit RENDERER")
    }
    
    init(cache: Cache) {
        self.cache = cache
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

extension BitmapRenderer {
    func render() {
        guard let ctx = self.ctx else { return }
        
        for (_, texture) in self.textures.sorted(by: { $0.value.order.rawValue < $1.value.order.rawValue }) {
            guard texture.visibility == YC_VID_TEXTURE_VISIBILITY_ON else { continue }
            
            ctx.draw(
                texture.frame.image,
                in: .init(
                    origin: .init(
                        x: texture.origin.x + texture.frame.shift.x,
                        y: CGFloat(ctx.height) - texture.origin.y + texture.frame.shift.y // CG coords are upside down
                    ),
                    size: .init(width: texture.frame.size.width, height: texture.frame.size.height)
                )
            )
        }
                
        DispatchQueue.main.async(execute: {
            self.canvas = .init(
                cgImage: ctx.makeImage()!,
                size: .init(width: ctx.width, height: ctx.height)
            )
        })
    }
    
    func invalidate(fully: Bool = false) {
        if fully { self.canvas = nil }
        
        self.cache.invalidate()
        self.textures.removeAll()
        self.ctx = nil
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
        
        let sprite = self.cache.fetch(for: yc_res_pro_fid_from(sprite_idx, type))
        let animation = sprite.animations[sprite.indexes[Int(orientation.rawValue)]]
        
        destination.pointee.fps = animation.fps
        destination.pointee.keyframe_idx = animation.keyframe_idx
        
        destination.pointee.count = animation.frames.count
        destination.pointee.textures = .allocate(capacity: animation.frames.count) // will be freed by the view
        
        for (index, frame) in animation.frames.enumerated() {
            let texture: Texture = .init(
                uuid: .init(),
                frame: frame,
                origin: .zero,
                order: YC_VID_TEXTURE_ORDER_NORMAL,
                visibility: YC_VID_TEXTURE_VISIBILITY_OFF
            )
            
            self.textures[texture.uuid] = texture
            
            // allocate and copy the handler. free later within invalidation
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
