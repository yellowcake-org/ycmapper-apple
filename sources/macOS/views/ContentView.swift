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
        
    @State
    private var map: yc_res_map_t = .init()
    
    @State
    private var view: yc_vid_view_t = .init()
    
    @State
    private var fetcher: Fetcher?
    
    @State
    private var renderer: BitmapRenderer?
    
    var body: some View {
        if self.fetcher == nil {
            Button(action: {
                self.isImporting.toggle()
            }, label: {
                Text("Open map")
            })
            .padding()
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
            if let canvas = self.renderer?.canvas {
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
        self.renderer = .init(cache: .init(fetcher: self.fetcher!))
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
            context: withUnsafePointer(to: fetcher, { $0 })) { pid, result, ctx in
                guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
                else { return YC_RES_MAP_STATUS_CORR }
                
                let parsed = fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_ITEM)
                let type = parsed.object.pointee.data.item.pointee.type
                
                yc_res_pro_object_invalidate(parsed.object)
                parsed.object.deallocate()
                
                result?.pointee = type
                return YC_RES_MAP_STATUS_OK
            } scenery_type_from_pid: { pid, result, ctx in
                guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
                else { return YC_RES_MAP_STATUS_CORR }
                
                let parsed = fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_SCENERY)
                let type = parsed.object.pointee.data.scenery.pointee.type
                
                yc_res_pro_object_invalidate(parsed.object)
                parsed.object.deallocate()
                
                result?.pointee = type
                return YC_RES_MAP_STATUS_OK
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
                self.renderer!.render()
                self.cleanup()
                
                self.isProcessing = false
            }
                    
            let renderer = yc_vid_renderer_t(
                context: withUnsafePointer(to: self.renderer!, { .init(mutating: $0) }),
                texture: withUnsafePointer(to: self.renderer!.callbacks, { $0 })
            )
            
            let status = yc_vid_view_initialize(
                &self.view,
                self.map.levels.0,
                withUnsafePointer(to: renderer, { $0 })
            )
            
            assert(status == YC_VID_STATUS_OK)
            
            let seconds = yc_vid_time_seconds(value: 0, scale: self.view.time.scale)
            let tick_status = yc_vid_view_frame_tick(
                &self.view,
                withUnsafePointer(to: renderer, { $0 }),
                withUnsafePointer(to: seconds, { $0 })
            )
            
            assert(YC_VID_STATUS_OK == tick_status)
        })
    }
}

extension ContentView {
    func cleanup() {
        let renderer = yc_vid_renderer_t(
            context: withUnsafePointer(to: self.renderer!, { .init(mutating: $0) }),
            texture: withUnsafePointer(to: self.renderer!.callbacks, { $0 })
        )
        
        yc_vid_view_invalidate(&self.view, withUnsafePointer(to: renderer, { $0 }) )
        yc_res_map_invalidate(&self.map)
        
        self.renderer?.invalidate()
    }
}
