//
//  map.swift
//  ycmapper
//
//  Created by Alexander Orlov on 30.04.2024.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct MapDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.init(filenameExtension: "map")!, .init(filenameExtension: "MAP")!] }
    static var writableContentTypes: [UTType] { [] }

    init(configuration: ReadConfiguration) throws {
        fatalError()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        fatalError()
    }
}
