//
//  ContentView.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    struct Elevation: Hashable, Equatable, Identifiable {
        static let empty = Self.init(idx: 0, ptr: nil)
        let id: UUID = .init()
        
        let idx: UInt8
        let ptr: UnsafeMutablePointer<yc_res_map_level_t>!
        
        var title: String { self.ptr == nil ? "None" : "Level \(self.idx + 1)" }
        var systemImage: String { self.ptr == nil ? "circle.dashed" : "\(self.idx + 1).circle" }
    }
    
    @State
    private var document = ImageDocument(image: nil)
    
    @State
    private var elevation: Elevation = .empty
    
    @State
    private var elevations: [Elevation] = [.empty, .init(idx: 0, ptr: nil), .init(idx: 0, ptr: nil)]
    
    @State
    private var layers: [Bool] = .init(repeating: true, count: Int(YC_VID_TEXTURE_ORDER_COUNT.rawValue)) {
        didSet {
            self.renderer?.layers = self.layers
            
            self.isProcessing = true
            DispatchQueue.global(qos: .userInitiated).async(execute: {
                defer { self.isProcessing = false }
                self.renderer?.render()
            })
        }
    }
    
    @State
    private var isImporting: Bool = false
    
    @State
    private var isExporting: Bool = false
        
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
        ZStack(content: {
            if self.fetcher == nil {
                Button(action: {
                    self.isImporting.toggle()
                }, label: {
                    Text("Open map")
                })
                .padding()
            } else {
                if self.elevation.ptr == nil && !self.isProcessing {
                    ContentUnavailableView(
                        "Empty elevation",
                        systemImage: "rectangle.dashed", // "pencil.slash"
                        description: Text("Selected elevation has no content.")
                    )
                } else {
                    if let canvas = self.renderer?.canvas {
                        GeometryReader { proxy in
                            ScrollView([.horizontal, .vertical], content: {
                                Image(nsImage: canvas)
                            })
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            }
        })
        .navigationTitle(Text(self.fetcher?.map.lastPathComponent ?? ""))
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
        .fileExporter(
            isPresented: self.$isExporting,
            document: self.document,
            contentType: UTType.png,
            defaultFilename: self.fetcher?.map
                .deletingPathExtension().lastPathComponent.appending("-\(self.elevation.idx + 1)"),
            onCompletion: { result in
                //
            }
        )
        .toolbar(content: {
            ToolbarItem(placement: .navigation, content: {
                Picker(
                    selection: self.$elevation,
                    content: {
                        ForEach(self.elevations, content: {
                            Label($0.title, systemImage: $0.systemImage).tag($0)
                        })
                    },
                    label: { EmptyView() }
                )
                .pickerStyle(.segmented)
                .disabled(self.isProcessing || self.fetcher == nil)
                .onChange(of: self.elevation, {
                    self.isProcessing = true
                    DispatchQueue.global(qos: .userInitiated).async(execute: {
                        defer { self.isProcessing = false }
                        
                        self.cleanup()
                        self.display()
                    })
                })
            })
            
            ToolbarItem(content: {
                if self.isProcessing { ProgressView().progressViewStyle(.circular).scaleEffect(0.6) }
            })
            
            ToolbarItem(content: {
                Menu(content: {
                    ForEach(Array(self.layers.enumerated()), id: \.offset, content: { (index, _) in
                        Button(action: {
                            var layers = self.layers
                            layers[index].toggle()
                            
                            self.layers = layers
                        }, label: {
                            HStack(content: {
                                self.layers[index] ?
                                Image(systemName: "checkmark.circle") : Image(systemName: "circle.dotted")
                                
                                Text(yc_vid_texture_order_t(rawValue: UInt32(index)).title())
                            })
                        })
                    })
                }, label: {
                    Label(
                        "Layers",
                        systemImage: self.layers.allSatisfy({ $0 }) ? "square.3.layers.3d" : "square.3.layers.3d.middle.filled"
                    )
                }).disabled(self.isProcessing || self.fetcher == nil)
            })
            
            ToolbarItem(content: {
                Button("Export", systemImage: "square.and.arrow.up", action: {
                    self.document = .init(image: self.renderer!.canvas!)
                    self.isExporting.toggle()
                }).disabled(self.isProcessing || self.renderer?.canvas == nil)
            })
        })
        .onDisappear(perform: { self.invalidate() })
    }
}


extension ContentView {
    func open(map: URL) {
        self.isProcessing = true
        
        defer {
            // escape current runloop for updated @State
            DispatchQueue.main.async(execute: {
                self.isProcessing = false
                self.parse()
            })
        }
        
        var root = map.deletingLastPathComponent()
        assert(root.lastPathComponent == "MAPS")
        root = root.deletingLastPathComponent()
        
        self.fetcher = .init(map: map, root: root)
        self.renderer = .init(
            cache: .init(fetcher: self.fetcher!),
            layers: self.layers
        )
    }
}

extension ContentView {
    func parse() {
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
            self.load()
        }
        
        guard var fetcher = self.fetcher
        else { return }
                
        var fetchers = yc_res_map_parse_db_api_t(
            context: withUnsafeMutablePointer(to: &fetcher, { $0 })
        ) { pid, result, ctx in
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
        let status = yc_res_map_parse(self.fetcher!.map.path, &io_fs_api, &fetchers, &result)
        
        assert(status == YC_RES_MAP_STATUS_OK)
        
        self.map = result.map.pointee
    }
}

extension ContentView {
    func load() {
        self.isProcessing = true
        defer { self.isProcessing = false }
                
        self.elevations = [
            (0, self.map.levels.0),
            (1, self.map.levels.1),
            (2, self.map.levels.2),
        ].map({ .init(idx: $0.0, ptr: $0.1) })
        
        self.elevation = self.elevations.first!
    }
}

extension ContentView {
    func display() {
        self.isProcessing = true
        defer { self.isProcessing = false }
        
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
        
        assert(status == YC_VID_STATUS_OK)

        var seconds = yc_vid_time_seconds(value: 0, scale: self.view.time.scale)
        let tick_status = yc_vid_view_frame_tick(
            &self.view,
            &tmp,
            &seconds
        )
        
        assert(YC_VID_STATUS_OK == tick_status)
        
        renderer.render()
    }
}

extension ContentView {
    func cleanup() {
        self.isProcessing = true
        defer { self.isProcessing = false }
        
        guard var context = self.renderer else { return }
        guard var callbacks = self.renderer?.callbacks else { return }
        
        var tmp = yc_vid_renderer_t(
            context: withUnsafeMutablePointer(to: &renderer, { $0 }),
            texture: withUnsafeMutablePointer(to: &callbacks, { $0 })
        )
        
        yc_vid_view_invalidate(&self.view, &tmp)
    }
}

extension ContentView {
    func invalidate() {
        self.cleanup()
        
        self.renderer?.invalidate()
        yc_res_map_invalidate(&self.map)
    }
}

extension yc_vid_texture_order_t {
    func title() -> String {
        switch self.rawValue {
        case YC_VID_TEXTURE_ORDER_FLOOR.rawValue: return "Floor"
        case YC_VID_TEXTURE_ORDER_FLAT.rawValue: return "Flats"
        case YC_VID_TEXTURE_ORDER_WALL.rawValue: return "Walls"
        case YC_VID_TEXTURE_ORDER_SCENERY.rawValue: return "Scenery"
        case YC_VID_TEXTURE_ORDER_MISC.rawValue: return "Miscellanea"
        case YC_VID_TEXTURE_ORDER_ITEM.rawValue: return "Items"
        case YC_VID_TEXTURE_ORDER_CRITTER.rawValue: return "Critters"
        case YC_VID_TEXTURE_ORDER_ROOF.rawValue: return "Roofs"
        default: return "Unknown"
        }
    }
}
