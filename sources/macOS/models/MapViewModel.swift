//
//  MapViewModel.swift
//  ycmapper
//
//  Created by Alexander Orlov on 30.04.2024.
//

import SwiftUI
import UniformTypeIdentifiers

extension MapView {
    class Model: ObservableObject {
        enum Error: Swift.Error { case path, parsing, rendering }
        
        struct State {
            var isImporting: Bool = false
            var isExporting: Bool = false
            var isProcessing: Bool = false
            
            var hasOpenedMap: Bool = false
        }
        
        struct Elevation: Hashable, Equatable, Identifiable {
            static let empty = Self.init(idx: 0, ptr: nil)
            
            let id: UUID = .init()
            let idx: UInt8
            let ptr: UnsafeMutablePointer<yc_res_map_level_t>!
            
            var title: String { self.ptr == nil ? "None" : "Level \(self.idx + 1)" }
            var systemImage: String { self.ptr == nil ? "circle.dashed" : "\(self.idx + 1).circle" }
        }
                
        @Published
        var error: Swift.Error?
        
        @Published
        var title: String? = nil
        
        @Published
        var document = ImageDocument(image: nil)
        
        @Published
        var exportName: String? = nil
        
        @Published
        var elevation: Elevation = .empty
        
        @Published
        var elevations: [Elevation] = [.empty, .empty, .empty]
        
        @Published
        var state: State = .init()
        
        @Published
        var types: [UTType] = [.init(filenameExtension: "map")!, .init(filenameExtension: "MAP")!]
        
        @Published
        var layers: [Bool] = .init(repeating: true, count: Int(YC_VID_TEXTURE_ORDER_COUNT.rawValue)) {
            didSet {
                DispatchQueue.main.async(execute: { self.state.isProcessing = true })
                
                DispatchQueue.global(qos: .userInitiated).async(execute: {
                    defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
                    
                    self.renderer?.layers = self.layers
                    self.renderer?.render()
                })
            }
        }
        
        @Published
        var renderer: BitmapRenderer?
        
        private var map: yc_res_map_t = .init()
        private var view: yc_vid_view_t = .init()
        
        private var fetcher: Fetcher? { didSet {
            self.state.hasOpenedMap = self.fetcher != nil
            self.title = self.fetcher?.map.lastPathComponent
            self.exportName = self.fetcher?.map
                .deletingPathExtension().lastPathComponent.appending("-\(self.elevation.idx + 1)")
        } }
    }
}

extension MapView.Model {
    func open(map: URL) throws {
        self.state.isProcessing = true
        
        defer {
            // escape current runloop for updated @State
            DispatchQueue.main.async(execute: {
                self.state.isProcessing = false
                do { try self.parse() } catch { self.error = error }
            })
        }
        
        var root = map.deletingLastPathComponent()
        guard root.lastPathComponent == "MAPS" else { throw Error.path }
        
        root = root.deletingLastPathComponent()
        
        self.fetcher = .init(map: map, root: root)
        self.renderer = try .init(
            cache: try .init(fetcher: self.fetcher!),
            layers: self.layers
        )
    }
}

extension MapView.Model {
    func parse() throws {
        self.state.isProcessing = true
        
        defer {
            self.state.isProcessing = false
            self.load()
        }
        
        guard var fetcher = self.fetcher
        else { return }
                
        var fetchers = yc_res_map_parse_db_api_t(
            context: withUnsafeMutablePointer(to: &fetcher, { $0 })
        ) { pid, result, ctx in
            guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
            else { return YC_RES_MAP_STATUS_CORR }
            
            guard let parsed = try? fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_ITEM)
            else { return YC_RES_MAP_STATUS_CORR }
                    
            let type = parsed.object.pointee.data.item.pointee.type
            
            yc_res_pro_object_invalidate(parsed.object)
            parsed.object.deallocate()
            
            result?.pointee = type
            return YC_RES_MAP_STATUS_OK
        } scenery_type_from_pid: { pid, result, ctx in
            guard let fetcher = ctx?.assumingMemoryBound(to: Fetcher.self).pointee
            else { return YC_RES_MAP_STATUS_CORR }
            
            guard let parsed = try? fetcher.prototype(identifier: pid, for: YC_RES_PRO_OBJECT_TYPE_SCENERY)
            else { return  YC_RES_MAP_STATUS_CORR }
            
            let type = parsed.object.pointee.data.scenery.pointee.type
            
            yc_res_pro_object_invalidate(parsed.object)
            parsed.object.deallocate()
            
            result?.pointee = type
            return YC_RES_MAP_STATUS_OK
        }
        
        
        var result = yc_res_map_parse_result_t(map: nil)
        let status = yc_res_map_parse(self.fetcher!.map.path, &io_fs_api, &fetchers, &result)
        
        guard status == YC_RES_MAP_STATUS_OK else { throw Error.parsing }
        
        self.map = result.map.pointee
    }
}

extension MapView .Model{
    func load() {
        DispatchQueue.main.async(execute: { self.state.isProcessing = true })
        defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
                
        self.elevations = [
            (0, self.map.levels.0),
            (1, self.map.levels.1),
            (2, self.map.levels.2),
        ].map({ .init(idx: $0.0, ptr: $0.1) })
        
        self.elevation = self.elevations.first ?? .empty
    }
}

extension MapView.Model {
    func display() throws {
        DispatchQueue.main.async(execute: { self.state.isProcessing = true })
        defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
                
        guard self.elevation.ptr != nil else { return }
        guard var renderer = self.renderer else { return }
        guard var callbacks = self.renderer?.callbacks else { return }
        
        var tmp = yc_vid_renderer_t(
            context: withUnsafeMutablePointer(to: &renderer, { $0 }),
            texture: withUnsafeMutablePointer(to: &callbacks, { $0 })
        )
        
        let status = yc_vid_view_initialize(
            &self.view,
            self.elevation.ptr!,
            &tmp
        )
        
        guard status == YC_VID_STATUS_OK else { throw Error.parsing }

        var seconds = yc_vid_time_seconds(value: 0, scale: self.view.time.scale)
        let tick_status = yc_vid_view_frame_tick(
            &self.view,
            &tmp,
            &seconds
        )
        
        guard tick_status == YC_VID_STATUS_OK else { throw Error.parsing }
        
        renderer.render()
    }
}

extension MapView.Model {
    func cleanup() {
        DispatchQueue.main.async(execute: { self.state.isProcessing = true })
        defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
        
        guard var context = self.renderer else { return }
        guard var callbacks = self.renderer?.callbacks else { return }
        
        var tmp = yc_vid_renderer_t(
            context: withUnsafeMutablePointer(to: &context, { $0 }),
            texture: withUnsafeMutablePointer(to: &callbacks, { $0 })
        )
        
        yc_vid_view_invalidate(&self.view, &tmp)
    }
}

extension MapView.Model {
    func invalidate() {
        self.cleanup()
        
        self.renderer?.invalidate()
        yc_res_map_invalidate(&self.map)
    }
}
