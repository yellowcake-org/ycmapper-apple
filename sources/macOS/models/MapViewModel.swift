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
        @Published
        var error: Swift.Error?
        enum Error: Swift.Error { case path, parsing, rendering }
        
        @Published
        var canvas: NSImage? = nil
        
        @Published
        var title: String? = nil
        
        @Published
        var export: Export = .init()
        struct Export {
            var filename: String?
            var document: ImageDocument?
        }
        
        @Published
        var elevations: [Elevation] = [.empty(), .empty(), .empty()]
        
        @Published
        var elevation: Elevation = .empty() { didSet { self.cleanup(completion: { [weak self] in self?.display() }) } }
        struct Elevation: Hashable, Equatable, Identifiable {
            static func empty() -> Self { .init(idx: 0, ptr: nil) }
            
            let id: UUID = .init()
            let idx: UInt8
            let ptr: UnsafeMutablePointer<yc_res_map_level_t>!
            
            var isEmpty: Bool { self.ptr == nil }
            
            var title: String { self.ptr == nil ? "None" : "Level \(self.idx + 1)" }
            var systemImage: String { self.isEmpty ? "circle.dashed" : "\(self.idx + 1).circle" }
        }
        
        @Published
        var state: State = .init()
        struct State {
            var isImporting: Bool = false
            var isExporting: Bool = false
            var isProcessing: Bool = false
            
            var hasOpenedMap: Bool = false
        }
        
        @Published
        var layers: [Bool] = .init(repeating: true, count: Int(YC_VID_TEXTURE_ORDER_COUNT.rawValue)) {
            didSet {
                self.renderer?.layers = self.layers
                self.cleanup(completion: { [weak self] in self?.display() })
            }
        }
        
        private let queues: Queues = .init()
        private struct Queues {
            let working: DispatchQueue = .init(label: "\(Self.self)-working")
        }
        
        private var map: yc_res_map_t = .init()
        private var view: yc_vid_view_t = .init()
        
        private var renderer: BitmapRenderer?
        private var fetcher: Fetcher? { didSet {
            self.state.hasOpenedMap = self.fetcher != nil
            
            guard let fetcher 
            else { self.title = nil; self.export.filename = nil; return }
            
            self.title = fetcher.map.lastPathComponent
            self.export.filename = fetcher.map.deletingPathExtension().lastPathComponent.appending("-\(self.elevation.idx + 1)")
        } }
    }
}

extension MapView.Model {
    func open(map: URL) {
        self.state.isProcessing = true
        self.queues.working.async(execute: {
            var root = map.deletingLastPathComponent()
            guard root.lastPathComponent == "MAPS" else { self.error = Error.path; return }
            root = root.deletingLastPathComponent()
            
            var fetcher: Fetcher? = .init(map: map, root: root)
            var renderer: BitmapRenderer? = nil
            var error: Swift.Error? = nil
            
            do { renderer = try .init(cache: try .init(fetcher: fetcher!), layers: self.layers) }
            catch (let e) {
                fetcher = nil
                error = e
            }
                        
            DispatchQueue.main.async(execute: {
                self.error = error
                
                self.fetcher = fetcher
                self.renderer = renderer
                
                self.state.isProcessing = false
                if error == nil { self.parse() }
            })
        })
    }
    
    func invalidate() {
        self.cleanup(completion: {
            self.renderer?.invalidate()
            yc_res_map_invalidate(&self.map)
            
            self.canvas = nil
        })
    }
}

private extension MapView.Model {
    func parse() {
        self.state.isProcessing = true
        self.queues.working.async(execute: {
            defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
            
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
            
            DispatchQueue.main.async(execute: {
                guard status == YC_RES_MAP_STATUS_OK
                else { self.error = Error.parsing; return }
                
                self.map = result.map.pointee
                self.setup()
            })
        })
    }
}

private extension MapView .Model{
    func setup() {        
        self.elevations = [
            (0, self.map.levels.0),
            (1, self.map.levels.1),
            (2, self.map.levels.2),
        ].map({ .init(idx: $0.0, ptr: $0.1) })
        
        self.elevation = self.elevations.first ?? .empty()
    }
}

private extension MapView.Model {
    func display() {
        self.state.isProcessing = true
        self.queues.working.async(execute: {
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
            
            guard status == YC_VID_STATUS_OK
            else { self.error = Error.parsing; return }

            var seconds = yc_vid_time_seconds(value: 0, scale: self.view.time.scale)
            let tick_status = yc_vid_view_frame_tick(
                &self.view,
                &tmp,
                &seconds
            )
            
            guard tick_status == YC_VID_STATUS_OK
            else { self.error =  Error.parsing; return }
            
            let result = renderer.render()
            DispatchQueue.main.async(execute: { self.canvas = result })
        })
    }
}

private extension MapView.Model {
    func cleanup(completion: (() -> ())? = nil) {
        self.state.isProcessing = true
        self.queues.working.async(execute: { [weak self] in
            defer { DispatchQueue.main.async(execute: { self?.state.isProcessing = false }) }
            defer { DispatchQueue.main.async(execute: { completion?() }) }
            
            guard let self else { return }
            guard var context = self.renderer else { return }
            guard var callbacks = self.renderer?.callbacks else { return }
            
            var tmp = yc_vid_renderer_t(
                context: withUnsafeMutablePointer(to: &context, { $0 }),
                texture: withUnsafeMutablePointer(to: &callbacks, { $0 })
            )
            
            yc_vid_view_invalidate(&self.view, &tmp)
        })
    }
}
