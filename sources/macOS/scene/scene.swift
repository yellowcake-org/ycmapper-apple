//
//  scene.swift
//  ycmapper
//
//  Created by Alexander Orlov on 07.05.2024.
//

import SpriteKit

class MapScene: SKScene {
    public let cache: Cache
    
    // TODO: Better get rid of it and have handles to be direct pointers to the texture.
    private var textures: [UUID : Texture] = .init()
    
    private var yc_level: yc_res_map_level_t
    private var yc_callbacks: yc_vid_texture_api_t?
    
    private var yc_view: yc_vid_view_t?
    private var yc_renderer: yc_vid_renderer_t?
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(fetcher: Fetcher, level: yc_res_map_level_t) throws {
        self.cache = try .init(fetcher: fetcher)
        self.yc_level = level
        
        super.init(size: .init(width: 8000, height: 3600))
        
        self.scaleMode = .aspectFill
        self.anchorPoint = .init(x: 0.0, y: 0.0)
        self.backgroundColor = .clear
        
        self.yc_callbacks = .init(
            initialize: { fid, orientation, destination, ctx  in
                guard let ctx else { return YC_VID_STATUS_CORRUPTED }
                let scene: MapScene = Unmanaged.fromOpaque(ctx).takeUnretainedValue()
                
                return scene.initialize(fid: fid, orientation: orientation, destination: destination)
            },
            invalidate: { texture, ctx in
                guard let ctx else { return YC_VID_STATUS_CORRUPTED }
                let scene: MapScene = Unmanaged.fromOpaque(ctx).takeUnretainedValue()
                
                return scene.invalidate(texture: texture)
            },
            is_equal: { lhs, rhs in
                lhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                ==
                rhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
            },
            set_visibility: { texture, visibility, order, ctx in
                guard let ctx else { return YC_VID_STATUS_CORRUPTED }
                let scene: MapScene = Unmanaged.fromOpaque(ctx).takeUnretainedValue()
                
                return scene.update(texture: texture, visibility: visibility, order: order)
            },
            set_coordinates: { texture, coordinates, ctx in
                guard let ctx else { return YC_VID_STATUS_CORRUPTED }
                let scene: MapScene = Unmanaged.fromOpaque(ctx).takeUnretainedValue()
                
                return scene.update(texture: texture, coordinates: coordinates)
            },
            set_indexes: { texture, indexes, scale, ctx in
                guard let ctx else { return YC_VID_STATUS_CORRUPTED }
                let scene: MapScene = Unmanaged.fromOpaque(ctx).takeUnretainedValue()
                
                return scene.update(texture: texture, indexes: indexes, scale: scale)
            }
        )

        self.yc_renderer = yc_vid_renderer_t(
            context: Unmanaged.passUnretained(self).toOpaque(),
            texture: withUnsafeMutablePointer(to: &self.yc_callbacks!, { $0 })
        )
        
        self.yc_view = .init()
        let status = yc_vid_view_initialize(
            withUnsafeMutablePointer(to: &self.yc_view!, { $0 }),
            withUnsafeMutablePointer(to: &self.yc_level, { $0 }),
            withUnsafeMutablePointer(to: &self.yc_renderer!, { $0 })
        )
        
        enum Error: Swift.Error { case initialization }
        guard status == YC_VID_STATUS_OK else {
            self.yc_view = nil
            throw Error.initialization
        }
    }
    
    deinit {
        if var yc_view {
            yc_vid_view_invalidate(&yc_view, withUnsafeMutablePointer(to: &self.yc_renderer!, { $0 }))
        }
    }
}

// MARK: - Cycling

extension MapScene {
    override func update(_ currentTime: TimeInterval) {
        var seconds = yc_vid_time_seconds(value: 0, scale: self.yc_view!.time.scale)
        let tick_status = yc_vid_view_frame_tick(
            withUnsafeMutablePointer(to: &self.yc_view!, { $0 }),
            withUnsafeMutablePointer(to: &self.yc_renderer!, { $0 }),
            &seconds
        )
        
        guard tick_status == YC_VID_STATUS_OK else { fatalError() }
    }
}

// MARK: - Platform API

private extension MapScene {
    func initialize(
        fid: UInt32,
        orientation: yc_res_math_orientation_t,
        destination: UnsafeMutablePointer<yc_vid_texture_set_t>?
    ) -> yc_vid_status_t {
        guard let destination = destination else { return YC_VID_STATUS_INPUT }
        
        let sprite: Cache.Sprite
        do { sprite = try self.cache.fetch(for: fid) } catch { return YC_VID_STATUS_CORRUPTED }
        
        let animation = sprite.animations[sprite.indexes[Int(orientation.rawValue)]]
        
        destination.pointee.fps = animation.fps
        destination.pointee.keyframe_idx = animation.keyframe_idx
        
        destination.pointee.count = animation.frames.count
        destination.pointee.textures = .allocate(capacity: animation.frames.count) // will be freed by the view
        
        for (index, frame) in animation.frames.enumerated() {
            let texture: Texture = .init(
                uuid: .init(),
                frame: frame,
                indexes: .init(x: .zero, y: .zero),
                grid: .zero,
                order: nil,
                visibility: YC_VID_TEXTURE_VISIBILITY_OFF
            )
                        
            self.textures[texture.uuid] = texture
            self.addChild(texture.node)
            
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
        
        self.textures[uuid]?.node.removeFromParent()
        self.textures.removeValue(forKey: uuid)
        
        return YC_VID_STATUS_OK
    }
}

// MARK: - Updates

private extension MapScene {
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        visibility: yc_vid_texture_visibility_t,
        order: yc_vid_texture_order_t
    ) -> yc_vid_status_t {
        guard let texture = texture else { return YC_VID_STATUS_INPUT }
        
        let uuid = texture.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        guard self.textures[uuid] != nil else { return YC_VID_STATUS_CORRUPTED }
        
        guard let texture = self.textures[uuid]
        else { return YC_VID_STATUS_CORRUPTED }
        
        texture.node.isHidden = visibility == YC_VID_TEXTURE_VISIBILITY_OFF
        
        return YC_VID_STATUS_OK
    }
    
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        coordinates: yc_vid_coordinates_t
    ) -> yc_vid_status_t {
        guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        else { return YC_VID_STATUS_INPUT }
        
        guard let texture = self.textures[uuid]
        else { return YC_VID_STATUS_CORRUPTED }
                
        let x = CGFloat(coordinates.x) + texture.frame.shift.x
        let y = self.size.height - (CGFloat(coordinates.y) + texture.frame.shift.y)
        
        texture.node.position = .init(x: x, y: y)
        
        return YC_VID_STATUS_OK
    }
    
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        indexes: yc_vid_indexes_t,
        scale: size_t
    ) -> yc_vid_status_t {
        guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
        else { return YC_VID_STATUS_INPUT }
        
        guard let texture = self.textures[uuid]
        else { return YC_VID_STATUS_CORRUPTED }
        
        texture.grid = scale
        texture.indexes = indexes
         
        let side: CGFloat = .init(texture.grid)
        
        let xScaled = (side - .init(texture.indexes.x)) / side
        let yScaled = .init(texture.indexes.y) / side
                
//        let sum = xScaled + yScaled

        let layerOrdered: CGFloat = .init(texture.order?.rawValue ?? 0) / .init(YC_VID_TEXTURE_ORDER_COUNT.rawValue - 1)
        let tileOrdered: CGFloat = 
        /*(sum > xScaled && sum > yScaled ? yScaled - xScaled : xScaled - yScaled) +*/ (xScaled + side * yScaled)
        
        texture.node.zPosition = layerOrdered + tileOrdered
            
        return YC_VID_STATUS_OK
    }
}
