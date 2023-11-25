//
//  io.swift
//  ycmapper
//
//  Created by Alexander Orlov on 23.11.2023.
//

public let io_fs_api = yc_res_io_fs_api_t(
    fopen: { filename, mode in .init(mutating: fopen(filename, mode)) },
    fclose: { file in file.flatMap({ fclose($0.assumingMemoryBound(to: FILE.self)) }) ?? -1 },
    fread: { dest, size, nitems, file in
        file.flatMap({ fread(dest, size, nitems, $0.assumingMemoryBound(to: FILE.self)) }) ?? -1
    },
    fseek: { file, num, mode in file.flatMap({ fseek($0.assumingMemoryBound(to: FILE.self), num, mode) }) ?? -1 }
)
