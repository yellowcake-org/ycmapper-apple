//
//  ContentView.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI
import AppKit

struct ContentView: View {        
    @State
    private var isImporting: Bool = false
        
    @State
    private var isProcessing: Bool = false
    
//    @State
//    private var hasFrame: Bool = false
        
    @State
    private var map: yc_res_map_t = .init()
    
    @State
    private var view: yc_vid_view_t = .init()
    
    @State
    private var fetcher: Fetcher?
    
    @StateObject
    private var renderer: BitmapRenderer = .init()
    
    var body: some View {
        if self.fetcher == nil {
            Button(action: {
                self.isImporting.toggle()
            }, label: {
                Text("Open map")
            })
            .padding()
            .onDisappear(perform: {
//                guard var view = self.view else { return }
//                guard var renderer = self.renderer else { return }
//    
//                yc_vid_view_invalidate(&view, &renderer)
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
                    case .success(let urls): self.open(map: urls.first!)
                    default: ()
                    }
                }
            )
        }
        
        if self.isProcessing {
            ContentUnavailableView(label: { Text("Loading...") })
        } else {
            if let canvas = self.renderer.canvas {
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
    func open(map: URL) {
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
            self.parse()
        }
        
        var root = map.deletingLastPathComponent()
        assert(root.lastPathComponent == "MAPS")
        root = root.deletingLastPathComponent()
        
        self.fetcher = .init(map: map, root: root)
    }
}

extension ContentView {
    func parse() {
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
            self.load()
        }
        
        guard let fetcher = self.fetcher
        else { return }
                
        var fetchers = yc_res_map_parse_db_api_t(
            context: withUnsafePointer(to: fetcher, { $0 })) { pid, ctx in
                guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
                else { return YC_RES_PRO_OBJECT_ITEM_TYPE_KEY }
                
                let result = fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_ITEM)
                let type = result.object.pointee.data.item.pointee.type
                
                yc_res_pro_object_invalidate(result.object)
                return type
            } scenery_type_from_pid: { pid, ctx in
                guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
                else { return YC_RES_PRO_OBJECT_SCENERY_TYPE_GENERIC }
                
                let result = fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_SCENERY)
                let type = result.object.pointee.data.scenery.pointee.type
                
                yc_res_pro_object_invalidate(result.object)
                return type
            }
        
        
        var result = yc_res_map_parse_result_t(map: nil)
        let status = yc_res_map_parse(fetcher.map.path, withUnsafePointer(to: io_fs_api, { $0 }), &fetchers, &result)
        
        assert(status == YC_RES_MAP_STATUS_OK)
        
        self.map = result.map.pointee
    }
}

extension ContentView {
    func load() {
        self.isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async(execute: {
            defer {
                self.renderer.render()
                self.isProcessing = false
            }
            
            guard let fetcher = self.fetcher else { return }
            
            var db_api = yc_vid_database_api(
                context: withUnsafePointer(to: fetcher, { .init(mutating: $0) }),
                fetch: { type, sprite_idx, result, ctx in
                    guard let result = result
                    else { return YC_VID_STATUS_INPUT }
                    
                    guard let ctx = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
                    else { return YC_VID_STATUS_INPUT }
                    
                    let parsed = ctx.sprite(at: sprite_idx, for: type)
                    result.pointee.frm.sprite = parsed.sprite
                    
                    // TODO: Find proper palette!
                    let pal_status = yc_res_pal_parse(
                        ctx.root.appending(path: "COLOR.PAL").path,
                        withUnsafePointer(to: io_fs_api, { $0 }),
                        &result.pointee.pal
                    )
                    
                    assert(YC_RES_PAL_STATUS_OK == pal_status)
                    
                    return YC_VID_STATUS_OK
                }
            )
        
            let native = yc_vid_renderer_t(
                context: withUnsafePointer(to: self.renderer, { .init(mutating: $0) }),
                texture: withUnsafePointer(to: self.renderer.callbacks, { $0 })
            )
            
            let status = yc_vid_view_initialize(&self.view, self.map.levels.0, withUnsafePointer(to: native, { $0 }), &db_api)
            
            assert(status == YC_VID_STATUS_OK)
            
            let seconds = yc_vid_time_seconds(value: 0, scale: self.view.time.scale)
            let tick_status = yc_vid_view_frame_tick(
                &self.view, withUnsafePointer(to: native, { $0 }), withUnsafePointer(to: seconds, { $0 })
            )
            
            assert(YC_VID_STATUS_OK == tick_status)
        })
    }
}
