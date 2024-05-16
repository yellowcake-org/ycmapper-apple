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
        enum Error: Swift.Error { case path, parsing, loading, rendering }
        
        var scene: MapScene? = nil
        
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
        var elevation: Elevation = .empty() { didSet { /* re-render */  } }
        struct Elevation: Hashable, Equatable, Identifiable {
            static func empty() -> Self { .init(idx: 0, ptr: nil) }
            
            let id: UUID = .init()
            let idx: UInt8
            let ptr: UnsafeMutablePointer<yc_res_map_level_t>!
            
            var isEmpty: Bool { self.ptr == nil }
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
                var enabled: [yc_vid_texture_order_t] = []
                
                for index in 0..<YC_VID_TEXTURE_ORDER_COUNT.rawValue {
                    if self.layers[Int(index)] { enabled.append(.init(index)) }
                }
                
                self.scene?.enabled = enabled

                self.scene?.isPaused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: {
                    self.scene?.isPaused = true
                })
            }
        }
        
        private let queues: Queues = .init()
        private struct Queues {
            let working: DispatchQueue = .init(label: "\(Self.self)-working")
        }
        
        private var yc_map_result: yc_res_map_parse_result_t? {
            didSet {
                self.state.hasOpenedMap = self.yc_map_result != nil
            }
        }
    }
}

extension MapView.Model {
    func invalidate() {
        self.scene = nil
        
        guard let result = self.yc_map_result
        else { return }
        
        yc_res_map_invalidate(result.map)
        result.map.deallocate()
    }
}

extension MapView.Model {
    func open(url: URL) {
        self.state.isProcessing = true
        self.queues.working.async(execute: {
            defer { DispatchQueue.main.async(execute: { self.state.isProcessing = false }) }
            
            var root = url.deletingLastPathComponent()
            guard root.lastPathComponent == "MAPS" else { self.error = Error.path; return }
            root = root.deletingLastPathComponent()
            
            var fetcher = Fetcher(map: url, root: root)
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
                else { return YC_RES_MAP_STATUS_CORR }
                
                let type = parsed.object.pointee.data.scenery.pointee.type
                
                yc_res_pro_object_invalidate(parsed.object)
                parsed.object.deallocate()
                
                result?.pointee = type
                return YC_RES_MAP_STATUS_OK
            }
            
            
            var result = yc_res_map_parse_result_t(map: nil)
            let status = yc_res_map_parse(url.path, &io_fs_api, &fetchers, &result)

            DispatchQueue.main.async(execute: {
                guard status == YC_RES_MAP_STATUS_OK
                else { self.error = Error.parsing; return }
                
                self.yc_map_result = result
                self.setup(url: url, fetcher: fetcher)
            })
        })
    }
}

private extension MapView .Model{
    func setup(url: URL, fetcher: Fetcher) {
        guard let yc_map_result else { fatalError() }
        
        self.elevations = [
            (0, yc_map_result.map.pointee.levels.0),
            (1, yc_map_result.map.pointee.levels.1),
            (2, yc_map_result.map.pointee.levels.2),
        ].map({ .init(idx: $0.0, ptr: $0.1) })
        
        // re-update on changes
        self.title = url.lastPathComponent
        self.export.filename = url.deletingPathExtension().lastPathComponent.appending("-\(self.elevation.idx + 1)")
        
        self.elevation = self.elevations.first ?? .empty()
        do { self.scene = try .init(fetcher: fetcher, level: self.elevation.ptr.pointee) }
        catch { self.error = error }
    }
}
