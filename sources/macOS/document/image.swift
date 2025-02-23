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
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.png] }
    
    let image: Data
    
    init(image: Data) { self.image = image }
    init(configuration: ReadConfiguration) throws { throw CancellationError() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let representation = NSBitmapImageRep(data: self.image)!
        let contents = representation.representation(using: .png, properties: [:])!
        
        return FileWrapper(regularFileWithContents: contents)
    }
    
}
