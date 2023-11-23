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

public class BitmapRenderer {
    public let callbacks: yc_vid_texture_api_t
    
    @Published
    private(set) public var canvas: NSImage? = nil
    
    private var textures: [UUID : Texture] = .init()
    private struct Texture {
        var uuid: UUID
        let image: CGImage
        let shift: CGPoint
        var rect: CGRect
        var isVisible: Bool
    }
    
    private let ctx = CGContext(
        data: nil, width: 8000, height: 3600,
        bitsPerComponent: 8, bytesPerRow: 4 * 8000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    
    public init(fetcher: Fetcher) {
        self.callbacks = yc_vid_texture_api_t { data, destination, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .initialize(data: data, destination: destination) ?? YC_VID_STATUS_CORRUPTED
        } invalidate: { texture, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .invalidate(texture: texture) ?? YC_VID_STATUS_CORRUPTED
        } is_equal: { lhs, rhs in
            lhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee 
            ==
            rhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        } set_visibility: { texture, visibility, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .update(texture: texture, visibility: visibility) ?? YC_VID_STATUS_CORRUPTED
        } set_coordinates: { texture, coordinates, ctx in
            ctx?.assumingMemoryBound(to: BitmapRenderer.self).pointee
                .update(texture: texture, coordinates: coordinates) ?? YC_VID_STATUS_CORRUPTED
        }
    }
}

// MARK: - Usage

public extension BitmapRenderer {
    func render() {
        for (_, texture) in self.textures {
            guard texture.isVisible else { continue }
            
            self.ctx.draw(
                texture.image,
                in: .init( // CG coords are upside down
                    origin: .init(x: texture.rect.origin.x, y: CGFloat(self.ctx.height) - texture.rect.origin.y),
                    size: .init(width: texture.rect.width, height: texture.rect.height)
                )
            )
        }
        
        self.canvas = .init(
            cgImage: self.ctx.makeImage()!,
            size: .init(width: self.ctx.width, height: self.ctx.height)
        )
    }
}

// MARK: - Lifecycle

private extension BitmapRenderer {
    func initialize(
        data: UnsafePointer<yc_vid_texture_data_t>?,
        destination: UnsafeMutablePointer<yc_vid_texture_t>?
    ) -> yc_vid_status_t {
        guard let data = data?.pointee else { return YC_VID_STATUS_INPUT }
        guard let destination = destination else { return YC_VID_STATUS_INPUT }
        
        var rgba: [UInt8] = Array(
            repeating: 0,
            count: Int(data.dimensions.horizontal * data.dimensions.vertical) * 4 // count(RGBA) == 4
        )
        
        let colors = Array(
            UnsafeBufferPointer(
                start: data.pixels,
                count: Int(data.dimensions.horizontal * data.dimensions.vertical)
            )
        )
        
        for v_idx in 0..<Int(data.dimensions.vertical) {
            for h_idx in 0..<Int(data.dimensions.horizontal) {
                let rows = v_idx * (Int(data.dimensions.horizontal) * 4)
                
                var color = colors[h_idx + v_idx * Int(data.dimensions.horizontal)]
                let isTransparent = yc_res_pal_color_is_transparent(&color)
                
                rgba[(h_idx * 4 + 0) + rows] = color.r
                rgba[(h_idx * 4 + 1) + rows] = color.g
                rgba[(h_idx * 4 + 2) + rows] = color.b
                rgba[(h_idx * 4 + 3) + rows] = isTransparent ? .min : .max
            }
        }
        
        let ref = CGContext(
            data: &rgba,
            width: Int(data.dimensions.horizontal),
            height: Int(data.dimensions.vertical),
            bitsPerComponent: 8, // UInt8
            bytesPerRow: Int(data.dimensions.horizontal) * 4, // count(RGBA) == 4
            space: .init(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
         
        let texture: Texture = .init(
            uuid: .init(),
            image: ref.makeImage()!,
            shift: .init(x: Int(data.shift.horizontal), y: Int(data.shift.vertical)),
            rect: .init(
                origin: .init(x: 0, y: 0),
                size: .init(width: CGFloat(data.dimensions.horizontal), height: CGFloat(data.dimensions.vertical))
            ),
            isVisible: false
        )
        
        self.textures[texture.uuid] = texture
        
        // dealloc in invalidation block
        destination.pointee.handle = .allocate(byteCount: MemoryLayout<UUID>.size, alignment: 0)
        destination.pointee.handle.copyMemory(
            from: withUnsafePointer(to: texture.uuid, { $0 }),
            byteCount: MemoryLayout<UUID>.size
        )
        
        return YC_VID_STATUS_OK
    }
    
    func invalidate(texture: UnsafeMutablePointer<yc_vid_texture_t>?) -> yc_vid_status_t {
        guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        else { return YC_VID_STATUS_INPUT }
        
        self.textures.removeValue(forKey: uuid)
        
        // freeing what alloced in init ^^^
        texture?.pointee.handle.deallocate()
        texture?.pointee.handle = nil
        
        return YC_VID_STATUS_OK
    }
}

// MARK: - Updates

private extension BitmapRenderer {
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        visibility: yc_vid_texture_visibility_t
    ) -> yc_vid_status_t {
        guard let texture = texture else { return YC_VID_STATUS_INPUT }
        let uuid = texture.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        
        guard self.textures[uuid] != nil else { return YC_VID_STATUS_CORRUPTED }
        self.textures[uuid]!.isVisible = visibility == YC_VID_TEXTURE_VISIBILITY_ON
        
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
        
        self.textures[uuid]?.rect.origin.x = CGFloat(coordinates.x)
        self.textures[uuid]?.rect.origin.y = CGFloat(coordinates.y)
        
        return YC_VID_STATUS_OK
    }
}
