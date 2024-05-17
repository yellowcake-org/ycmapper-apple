//
//  MapView.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI
import SpriteKit

struct MapView: View {
    @StateObject
    var model: Model = .init()
    
    var body: some View {
        ZStack(content: {
            if !self.model.state.hasOpenedMap {
                self.welcome()
            } else if let _ = self.model.error {
                self.error()
            } else if let scene = self.model.scene {
                self.content(scene: scene)
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
            onCompletion: { if case let .success(urls) = $0 { self.model.open(url: urls.first!) } }
        )
        .fileExporter(
            isPresented: self.$model.state.isExporting,
            document: self.model.export.document,
            contentType: ImageDocument.writableContentTypes.first!,
            defaultFilename: self.model.export.filename,
            onCompletion: { _ in self.model.export.document = nil }
        )
    }
    
    @ViewBuilder
    private func error() -> some View {
        ContentUnavailableView(
            label: { Label { Text("screen.map.error.title") } icon: { Image(systemName: "xmark.rectangle") } },
            description: { Text("screen.map.error.description") }
        )
    }
    
    @ViewBuilder
    private func empty() -> some View {
        ContentUnavailableView(
            label: { Label { Text("screen.map.empty.title") } icon: { Image(systemName: "rectangle.dashed") } },
            description: { Text("screen.map.empty.description") }
        )
    }
    
    @ViewBuilder
    private func welcome() -> some View {
        ContentUnavailableView(
            label: { Label { Text("screen.map.welcome.title") } icon: { Image(systemName: "filemenu.and.selection") } },
            description: { Text("screen.map.welcome.description") },
            actions: {
                Button(
                    action: { self.model.state.isImporting.toggle() },
                    label: { Text("screen.map.welcome.action").padding() }
                )
                .buttonStyle(.bordered)
            }
        )
    }
    
    @ViewBuilder
    private func content(scene: MapScene) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                PositionReadableScrollView(axes: [.horizontal, .vertical], content: {
                    Rectangle()
                        .id(0)
                        .foregroundColor(.clear)
                        .background(.clear)
                        .frame(width: scene.size.width, height: scene.size.height)
                }, onScroll: { point in
                    self.model.scene?.camera?.xScale = geometry.size.width / scene.size.width
                    self.model.scene?.camera?.yScale = geometry.size.height / scene.size.height
                    self.model.scene?.camera?.position = .init(x: point.x, y: scene.size.height - point.y)
                })
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(content: {
                    SpriteView(scene: scene)
                        .background(.clear)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear(perform: { withAnimation(.none, { scroll.scrollTo(0, anchor: .center) }) })
                        .onAppear(perform: {
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + .milliseconds(100),
                                execute: { self.model.scene?.isPaused = true }
                            )
                        })
                })
            }
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
                        content: { Label("", systemImage: $0.systemImage).tag($0) }
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
            Button(
                action: {
                    self.model.snapshot()
                },
                label: { Label(title: { Text("screen.map.sheet.action") }, icon: { Image(systemName: "square.and.arrow.up") })}
            )
            .disabled(
                !self.model.state.hasOpenedMap ||
                self.model.state.isProcessing ||
                self.model.error != nil
            )
        })
    }
}

extension yc_vid_texture_order_t {
    func title() -> LocalizedStringKey {
        switch self.rawValue {
        case YC_VID_TEXTURE_ORDER_FLOOR.rawValue: return "screen.map.toolbar.layers.floor"
        case YC_VID_TEXTURE_ORDER_FLAT.rawValue: return "screen.map.toolbar.layers.flats"
        case YC_VID_TEXTURE_ORDER_WALL.rawValue: return "screen.map.toolbar.layers.walls"
        case YC_VID_TEXTURE_ORDER_SCENERY.rawValue: return "screen.map.toolbar.layers.scenery"
        case YC_VID_TEXTURE_ORDER_MISC.rawValue: return "screen.map.toolbar.layers.miscellanea"
        case YC_VID_TEXTURE_ORDER_ITEM.rawValue: return "screen.map.toolbar.layers.items"
        case YC_VID_TEXTURE_ORDER_CRITTER.rawValue: return "screen.map.toolbar.layers.critters"
        case YC_VID_TEXTURE_ORDER_ROOF.rawValue: return "screen.map.toolbar.layers.roofs"
        default: return "screen.map.toolbar.layers.unknown"
        }
    }
}

struct PositionReadableScrollView<Content>: View where Content: View {
    let axes: Axis.Set
    let content: () -> Content
    let onScroll: (CGPoint) -> Void
    
    var body: some View {
        ScrollView(self.axes) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.frame(in: .named("scrollID")).origin) { position, _ in
                                onScroll(.init(x: -position.x, y: -position.y))
                            }
                    }
                )
        }
        .coordinateSpace(.named("scrollID"))
    }
}

