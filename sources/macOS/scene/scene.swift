//
//  scene.swift
//  ycmapper
//
//  Created by Alexander Orlov on 07.05.2024.
//

import SpriteKit

class MapScene: SKScene {
    public let cache: Cache
    public var enabled: [yc_vid_texture_order_t] = [] {
        didSet { 
            self.textures.forEach({ _, texture in
                texture.isEnabled = texture.order.flatMap({
                    self.enabled.contains(yc_vid_texture_order_t(rawValue: $0.rawValue))
                }) ?? false
            })
        }
    }
    
    private var yc_level: yc_res_map_level_t
    
    private var yc_view: yc_vid_view_t?
    private var yc_renderer: yc_vid_renderer_t?
    private var yc_callbacks: yc_vid_texture_api_t?

    private var layers: [SKNode] = []
    private var textures: [UUID : Texture] = .init()
    
    private var last: TimeInterval?
    private var accumulated: TimeInterval = 0.0
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(fetcher: Fetcher, level: yc_res_map_level_t) throws {
        self.cache = try .init(fetcher: fetcher)
        self.yc_level = level
        
        for index in 0..<YC_VID_TEXTURE_ORDER_COUNT.rawValue {
            self.enabled.append(.init(index))
        }
        
        super.init(size: .init(width: 0, height: 0))
        
        self.backgroundColor = .clear
        self.scaleMode = .resizeFill
        
        let camera = SKCameraNode()
        
        self.camera = camera
        self.addChild(camera)
        
        for index in 0..<YC_VID_TEXTURE_ORDER_COUNT.rawValue {
            if ((YC_VID_TEXTURE_ORDER_FLAT.rawValue + 1 + 1)..<YC_VID_TEXTURE_ORDER_ROOF.rawValue).contains(index) {
                self.layers.append(self.layers[Int(YC_VID_TEXTURE_ORDER_FLAT.rawValue) + 1])
            } else {
                let layer = SKNode()
                layer.zPosition = .init(index)
                
                self.addChild(layer)
                self.layers.append(layer)
            }
        }
        
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
                guard let lhs, let rhs else { return false }
                
                let lt: Texture = Unmanaged.fromOpaque(lhs.pointee.handle).takeUnretainedValue()
                let rt: Texture = Unmanaged.fromOpaque(rhs.pointee.handle).takeUnretainedValue()
                
                return lt == rt
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
        
        guard status == YC_VID_STATUS_OK else {
            self.yc_view = nil

            enum Error: Swift.Error { case initialization }
            throw Error.initialization
        }
        
        self.cache.invalidate()
    }
    
    deinit {
        if var yc_view {
            yc_vid_view_invalidate(
                &yc_view,
                withUnsafeMutablePointer(to: &self.yc_renderer!, { $0 })
            )
        }
    }
}

// MARK: - Lifecycle

extension MapScene {
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        
        DispatchQueue.main.async(execute: {
            self.view?.allowsTransparency = true
            self.view?.ignoresSiblingOrder = false
            self.view?.disableDepthStencilBuffer = true
            self.view?.shouldCullNonVisibleNodes = true
            
            self.view?.showsFPS = true
            self.view?.showsDrawCount = true
            self.view?.showsNodeCount = true
            self.view?.showsQuadCount = true
        })
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        guard let view else { return }
        
        self.camera!.xScale = view.bounds.size.width / self.size.width
        self.camera!.yScale = view.bounds.size.height / self.size.height
    }
}

// MARK: - Cycling

extension MapScene {
    override func update(_ currentTime: TimeInterval) {
        defer { self.last = currentTime }
        guard let last else { return }
        
        let difference = (currentTime - last)
        self.accumulated += difference
        
        let units: UInt = .init(floor(self.accumulated * .init(self.yc_view!.time.scale)))
        guard units > 0 else { return }
        
        self.accumulated -= .init(units) / .init(self.yc_view!.time.scale)
        
        var seconds = yc_vid_time_seconds(
            value: .init(units),
            scale: self.yc_view!.time.scale
        )
        
        let tick_status = yc_vid_view_frame_tick(
            withUnsafeMutablePointer(to: &self.yc_view!, { $0 }),
            withUnsafeMutablePointer(to: &self.yc_renderer!, { $0 }),
            &seconds
        )
        
        guard tick_status == YC_VID_STATUS_OK else { return assertionFailure() }
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
        
        let animation = sprite.animations[sprite.indexes[.init(orientation.rawValue)]]
                
        destination.pointee.count = animation.frames.count
        destination.pointee.textures = .allocate(capacity: animation.frames.count * MemoryLayout<yc_vid_texture_t>.size)
        
        destination.pointee.fps = animation.fps
        destination.pointee.keyframe_idx = animation.keyframe_idx
        
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
            destination.pointee.textures.advanced(by: index).pointee.handle = Unmanaged.passUnretained(texture).toOpaque()
        }
        
        return YC_VID_STATUS_OK
    }
    
    func invalidate(texture: UnsafeMutablePointer<yc_vid_texture_t>?) -> yc_vid_status_t {
        guard let raw = texture else { return YC_VID_STATUS_INPUT }
        let texture: Texture = Unmanaged.fromOpaque(raw.pointee.handle).takeUnretainedValue()

        raw.pointee.handle = nil
        
        self.textures.removeValue(forKey: texture.uuid)
        texture.node.removeFromParent()
        
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
        guard let raw = texture else { return YC_VID_STATUS_INPUT }
        let texture: Texture = Unmanaged.fromOpaque(raw.pointee.handle).takeUnretainedValue()
        
        if texture.order != order {
            texture.node.removeFromParent()
            self.layers[Int(order.rawValue)].addChild(texture.node)
        }
        
        texture.order = order
        texture.visibility = visibility
        
        return YC_VID_STATUS_OK
    }
    
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        coordinates: yc_vid_coordinates_t
    ) -> yc_vid_status_t {
        guard let raw = texture else { return YC_VID_STATUS_INPUT }
        let texture: Texture = Unmanaged.fromOpaque(raw.pointee.handle).takeUnretainedValue()
                
        let x = CGFloat(coordinates.x)
        let y = self.size.height - CGFloat(coordinates.y)
        
        texture.node.position = .init(x: x, y: y)
        
        return YC_VID_STATUS_OK
    }
    
    func update(
        texture: UnsafeMutablePointer<yc_vid_texture_t>?,
        indexes: yc_vid_indexes_t,
        scale: size_t
    ) -> yc_vid_status_t {
        guard let raw = texture else { return YC_VID_STATUS_INPUT }
        let texture: Texture = Unmanaged.fromOpaque(raw.pointee.handle).takeUnretainedValue()
        
        texture.grid = scale
        texture.indexes = indexes
         
        let side: CGFloat = .init(texture.grid)
        let square = side * side
        
        let x: CGFloat = side - .init(texture.indexes.x)
        let y: CGFloat = .init(texture.indexes.y)

        texture.node.zPosition = ((x + side * y) / square)

        return YC_VID_STATUS_OK
    }
}
