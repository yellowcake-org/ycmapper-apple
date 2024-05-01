//
//  image.swift
//  ycmapper
//
//  Created by Alexander Orlov on 29.11.2023.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var image: NSImage?
    
    init(image: NSImage?) { self.image = image }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let image = NSImage(data: data)
        else { throw CocoaError(.fileReadCorruptFile) }
        
        self.image = image
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let representation = NSBitmapImageRep(data: self.image!.tiffRepresentation!)!
        let contents = representation.representation(using: .png, properties: [:])!
        
        return FileWrapper(regularFileWithContents: contents)
    }
    
}
