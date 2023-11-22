//
//  ContentView.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI
import AppKit

struct ContentView: View {
    struct Texture {
        var uuid: UUID
        let image: CGImage
        let shift: CGPoint
        var rect: CGRect
        var isVisible: Bool
    }
    
    struct Database {
        let map: URL
        let root: URL
    }
    
    struct World {
        let map: yc_res_map_t
    }
    
    @State
    private var isImporting: Bool = false
        
    @State
    private var isProcessing: Bool = false
    
    @State
    private var database: Database?
    
    @State
    private var world: World?
    
    @State
    private var view: yc_vid_view_t?
    
    @State
    private var renderer: yc_vid_renderer_t?
    
    @State
    private var textures: [UUID : Texture] = .init()
    
    @State
    private var canvas: NSImage? = nil
    
    private let ctx = CGContext(
        data: nil, width: 8000, height: 3600,
        bitsPerComponent: 8, bytesPerRow: 4 * 8000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    
    var body: some View {
        if self.database == nil {
            Button(action: {
                self.isImporting.toggle()
            }, label: {
                Text("Open map")
            })
            .padding()
            .onDisappear(perform: {
    //            guard var view = self.view else { return }
    //            guard var renderer = self.renderer else { return }
    //
    //            yc_vid_view_invalidate(&view, &renderer)
            })
            .onDisappear(perform: {
//                guard var map = self.world?.map else { return }
//                yc_res_map_invalidate(&map)
            })
            .fileImporter(
                isPresented: self.$isImporting,
                allowedContentTypes: [.init(filenameExtension: "map")!, .init(filenameExtension: "MAP")!],
                allowsMultipleSelection: false,
                onCompletion: { result in
                    switch result {
                    case .success(let urls): self.process(map: urls.first!)
                    default: ()
                    }
                }
            )
        }
        
        if self.isProcessing {
            ContentUnavailableView(label: { Text("Loading...") })
        } else {
            if !self.textures.isEmpty, let canvas = self.canvas {
                GeometryReader(content: { proxy in
                    ScrollView([.horizontal, .vertical], content: {
                        Image(nsImage: canvas)
                    })
                    .frame(width: proxy.size.width, height: proxy.size.height)
                })
            }
        }
    }
}


extension ContentView {
    func process(map: URL) {
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
            self.parse()
        }
        
        var root = map.deletingLastPathComponent()
        assert(root.lastPathComponent == "MAPS")
        root = root.deletingLastPathComponent()
        
        self.database = .init(map: map, root: root)
    }
}

extension ContentView {
    func parse() {
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
            self.load()
        }
        
        guard let database = self.database
        else { return }
        
        typealias ycmapper_pro_parser_t = ((UInt32, yc_res_pro_object_type) -> yc_res_pro_parse_result_t)
        let pro_parser: ycmapper_pro_parser_t = { pid, type in
            Fetchers.prototype(within: database.root, identifier: pid, for: type)
        }
        
        struct Context { var parser: ycmapper_pro_parser_t }
        let ctx = Context(parser: pro_parser)
        
        var fetchers = yc_res_map_parse_db_api_t(
            context: withUnsafePointer(to: ctx, { $0 })) { pid, ctx in
                guard let ctx = ctx?.assumingMemoryBound(to: Context.self).pointee
                else { return YC_RES_PRO_OBJECT_ITEM_TYPE_KEY }
                
                let result = ctx.parser(pid, YC_RES_PRO_OBJECT_TYPE_ITEM)
                let type = result.object.pointee.data.item.pointee.type
                
                yc_res_pro_object_invalidate(result.object)
                return type
            } scenery_type_from_pid: { pid, ctx in
                guard let ctx = ctx?.assumingMemoryBound(to: Context.self).pointee
                else { return YC_RES_PRO_OBJECT_SCENERY_TYPE_GENERIC }
                
                let result = ctx.parser(pid, YC_RES_PRO_OBJECT_TYPE_SCENERY)
                let type = result.object.pointee.data.scenery.pointee.type
                
                yc_res_pro_object_invalidate(result.object)
                return type
            }
        
        
        var result = yc_res_map_parse_result_t(map: nil)
        let status = yc_res_map_parse(database.map.path, withUnsafePointer(to: io_fs_api, { $0 }), &fetchers, &result)
        
        assert(status == YC_RES_MAP_STATUS_OK)
        self.world = .init(map: result.map.pointee)
    }
}

extension ContentView {
    func load() {
        self.isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async(execute: {
            defer {
                self.isProcessing = false
                self.render()
            }
            
            guard let world = self.world
            else { return }
            
            guard let database = self.database
            else { return }
            
            let ts_api = yc_vid_texture_api_t { data, destination, ctx in
                guard let data = data?.pointee else { return YC_VID_STATUS_INPUT }
                guard let destination = destination else { return YC_VID_STATUS_INPUT }
                guard let ctx = ctx else { return YC_VID_STATUS_INPUT }
                
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
                
                ctx.assumingMemoryBound(to: ContentView.self).pointee.textures[texture.uuid] = texture
                
                destination.pointee.handle = .allocate(byteCount: MemoryLayout<UUID>.size, alignment: 0)
                destination.pointee.handle.copyMemory(
                    from: withUnsafePointer(to: texture.uuid, { $0 }),
                    byteCount: MemoryLayout<UUID>.size
                )
                
                return YC_VID_STATUS_OK
            } invalidate: { texture, ctx in
                guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                else { return YC_VID_STATUS_INPUT }
                
                guard let ctx = ctx
                else { return YC_VID_STATUS_INPUT }
                
                ctx.assumingMemoryBound(to: ContentView.self).pointee.textures.removeValue(forKey: uuid)
                texture?.pointee.handle = nil
                
                return YC_VID_STATUS_OK
            } is_equal: { lhs, rhs in
                let luuid = lhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                let ruuid = rhs?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                
                return luuid == ruuid
            } set_visibility: { texture, visibility, ctx in
                guard let ctx = ctx else { return YC_VID_STATUS_INPUT }
                guard let texture = texture else { return YC_VID_STATUS_INPUT }
                
                let uuid = texture.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                let `self` = ctx.assumingMemoryBound(to: ContentView.self).pointee
  
                self.textures[uuid]!.isVisible = visibility == YC_VID_TEXTURE_VISIBILITY_ON
                
                return YC_VID_STATUS_OK
            } set_coordinates: { texture, coordinates, ctx in
                guard let ctx = ctx else { return YC_VID_STATUS_INPUT }
                
                guard let uuid = texture?.pointee.handle.assumingMemoryBound(to: UUID.self).pointee
                else { return YC_VID_STATUS_INPUT }
                
                ctx.assumingMemoryBound(to: ContentView.self).pointee.textures[uuid]!.rect.origin.x = CGFloat(coordinates.x)
                ctx.assumingMemoryBound(to: ContentView.self).pointee.textures[uuid]!.rect.origin.y = CGFloat(coordinates.y)
                
                return YC_VID_STATUS_OK
            }
            
            typealias ycmapper_frm_parser_t = ((yc_res_pro_object_type, UInt16) -> yc_res_frm_parse_result_t)
            let frm_parser: ycmapper_frm_parser_t = { type, index in
                Fetchers.sprite(within: database.root, at: index, for: type)
            }
                        
            struct Context {
                var parser: ycmapper_frm_parser_t
                var root: URL
                var fs_api: UnsafePointer<yc_res_io_fs_api_t>
            }
            
            let db_ctx = Context(
                parser: frm_parser,
                root: database.root,
                fs_api: withUnsafePointer(to: io_fs_api, { $0 })
            )
        
            var db_api = yc_vid_database_api(
                context: .init(mutating: withUnsafePointer(to: db_ctx, { $0 }))
            ) { type, sprite_idx, result, ctx in
                guard let result = result
                else { return YC_VID_STATUS_INPUT }
                
                guard let ctx = ctx?.assumingMemoryBound(to: Context.self).pointee
                else { return YC_VID_STATUS_INPUT }
                
                let parsed = ctx.parser(type, sprite_idx)
                result.pointee.frm.sprite = parsed.sprite
                
                // TODO: Find proper palette!
                let pal_status = yc_res_pal_parse(ctx.root.appending(path: "COLOR.PAL").path, ctx.fs_api, &result.pointee.pal)
                assert(YC_RES_PAL_STATUS_OK == pal_status)
                
                return YC_VID_STATUS_OK
            }
            
            var renderer = yc_vid_renderer_t(
                context: .init(mutating: withUnsafePointer(to: self, { $0 })),
                texture: withUnsafePointer(to: ts_api, { $0 })
            )
            
            var result = yc_vid_view_t()
            let status = yc_vid_view_initialize(&result, world.map.levels.0, &renderer, &db_api)
            
            assert(status == YC_VID_STATUS_OK)
            
            self.view = result
            self.renderer = renderer
            
            var seconds = yc_vid_time_seconds(value: 0, scale: result.time.scale)
            let tick_status = yc_vid_view_frame_tick(&result, &renderer, &seconds)
        
            assert(YC_VID_STATUS_OK == tick_status)
        })
    }
}

extension ContentView {
    func render() {
        for (_, texture) in self.textures {
            guard texture.isVisible else { continue }
            
            self.ctx.draw(
                texture.image,
                in: .init( // CG coords are upside down
                    origin: .init(x: texture.rect.origin.x, y: CGFloat(self.ctx.height) - texture.rect.origin.y),
                    size: .init(width: texture.rect.width, height: texture.rect.height)
                ),
                byTiling: false
            )
        }
        
        self.canvas = .init(
            cgImage: self.ctx.makeImage()!,
            size: .init(width: self.ctx.width, height: self.ctx.height)
        )
    }
}
