//
//  MapView.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI

struct MapView: View {
    @StateObject
    var model: Model = .init()
    
    var body: some View {
        ZStack(content: {
            if !self.model.state.hasOpenedMap {
                self.welcome()
            } else if let _ = self.model.error {
                self.error()
            } else if let canvas = self.model.canvas {
                self.content(canvas: canvas)
            } else if self.model.elevation.isEmpty && !self.model.state.isProcessing {
                self.empty()
            }
        })
        .onDisappear(perform: { self.model.invalidate() })
        .navigationTitle(Text(self.model.title ?? ""))
        .toolbar(content: {
            self.levels()
            self.loader()
            self.layers()
            self.sheet()
        })
        .fileImporter(
            isPresented: self.$model.state.isImporting,
            allowedContentTypes: MapDocument.readableContentTypes,
            allowsMultipleSelection: false,
            onCompletion: { if case let .success(urls) = $0 { self.model.open(map: urls.first!) } }
        )
        .fileExporter(
            isPresented: self.$model.state.isExporting,
            document: self.model.export.document,
            contentType: ImageDocument.writableContentTypes.first!,
            defaultFilename: self.model.export.filename,
            onCompletion: { _ in }
        )
    }
    
    @ViewBuilder
    private func error() -> some View {
        ContentUnavailableView(
            "Couldn't load",
            systemImage: "xmark.rectangle",
            description: Text("Please, check path to the file and if all resources are in place.")
        )
    }
    
    @ViewBuilder
    private func empty() -> some View {
        ContentUnavailableView(
            "Empty elevation",
            systemImage: "rectangle.dashed",
            description: Text("Selected elevation has no content.")
        )
    }
    
    @ViewBuilder
    private func welcome() -> some View {
        Button(
            action: { self.model.state.isImporting.toggle() },
            label: { Text("Open map") }
        ).padding()
    }
    
    @ViewBuilder
    private func content(canvas: NSImage) -> some View {
        GeometryReader { geometry in
            ScrollViewReader(content: { scroll in
                ScrollView(
                    [.horizontal, .vertical],
                    content: {
                        Image(nsImage: canvas)
                            .antialiased(false)
                            .interpolation(.none)
                            .id(0)
                            .onAppear(perform: { withAnimation(.none, { scroll.scrollTo(0, anchor: .center) }) })
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            })
        }
    }
    
    @ToolbarContentBuilder
    private func levels() -> some ToolbarContent {
        ToolbarItem(placement: .navigation, content: {
            Picker(
                selection: self.$model.elevation,
                content: {
                    ForEach(
                        self.model.elevations,
                        content: { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    )
                },
                label: { EmptyView() }
            )
            .pickerStyle(.segmented)
            .disabled(
                !self.model.state.hasOpenedMap ||
                self.model.state.isProcessing ||
                self.model.error != nil
            )
        })
    }
    
    @ToolbarContentBuilder
    private func loader() -> some ToolbarContent {
        ToolbarItem(content: {
            if self.model.state.isProcessing { ProgressView().progressViewStyle(.circular).scaleEffect(1.0 / 2.0) }
        })
    }
    
    @ToolbarContentBuilder
    private func layers() -> some ToolbarContent {
        ToolbarItem(content: {
            Menu(content: {
                ForEach(Array(self.model.layers.enumerated()), id: \.offset, content: { (index, _) in
                    Button(action: {
                        var layers = self.model.layers
                        layers[index].toggle()
                        
                        // This way the state will be toggled.
                        self.model.layers = layers
                    }, label: {
                        HStack(content: {
                            self.model.layers[index] ?
                            Image(systemName: "checkmark.circle") :
                            Image(systemName: "circle.dotted")
                            
                            Text(yc_vid_texture_order_t(rawValue: UInt32(index)).title())
                        })
                    })
                })
            }, label: {
                Label(
                    "Layers",
                    systemImage: self.model.layers.allSatisfy({ $0 }) ? "square.3.layers.3d" : "square.3.layers.3d.middle.filled"
                )
            })
            .disabled(
                !self.model.state.hasOpenedMap ||
                self.model.state.isProcessing ||
                self.model.error != nil
            )
        })
    }
     
    @ToolbarContentBuilder
    private func sheet() -> some ToolbarContent {
        ToolbarItem(content: {
            Button("Export", systemImage: "square.and.arrow.up", action: {
                self.model.export.document = .init(image: self.model.canvas!)
                self.model.state.isExporting.toggle()
            })
            .disabled(
                !self.model.state.hasOpenedMap ||
                self.model.state.isProcessing ||
                self.model.error != nil
            )
        })
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
