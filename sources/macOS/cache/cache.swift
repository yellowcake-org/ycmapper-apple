//
//  cache.swift
//  ycmapper
//
//  Created by Alexander Orlov on 26.11.2023.
//

import Foundation

class Cache {
    enum Error: Swift.Error {
        case palette
    }
    
    public let fetcher: Fetcher
    
    private var sprites: [UInt32 : Sprite] = .init()
    private var palette: yc_res_pal_parse_result_t = .init()
    
    deinit {
        self.palette.colors.deallocate()
    }
    
    init(fetcher: Fetcher) throws {
        self.fetcher = fetcher
        
        let status = yc_res_pal_parse(
            self.fetcher.root.appending(path: "COLOR.PAL").path,
            &io_fs_api,
            &self.palette
        )
        
        guard status == YC_RES_PAL_STATUS_OK else { throw Error.palette }
    }
}

extension Cache {
    func fetch(for fid: UInt32) -> Sprite {
        guard let sprite = self.sprites[fid] else {
            let index = yc_res_pro_index_from_sprite_id(fid)
            let type = yc_res_pro_object_type_from_fid(fid)
            
            let parsed = self.fetcher.sprite(fid: fid)
            defer { yc_res_frm_sprite_invalidate(parsed.0.sprite); parsed.0.sprite.deallocate() }
            
            let animations: [Sprite.Animation] = Array(
                UnsafeBufferPointer(
                    start: parsed.0.sprite.pointee.animations,
                    count: parsed.0.sprite.pointee.count
                )
            ).map({ .init(raw: $0, palette: palette) })
            
            let sprite: Sprite = .init(
                id: fid,
                idx: index,
                type: type,
                indexes: [
                    parsed.0.sprite.pointee.orientations.0,
                    parsed.0.sprite.pointee.orientations.1,
                    parsed.0.sprite.pointee.orientations.2,
                    parsed.0.sprite.pointee.orientations.3,
                    parsed.0.sprite.pointee.orientations.4,
                    parsed.0.sprite.pointee.orientations.5,
                ],
                animations: animations
            )
            
            self.sprites[fid] = sprite
            
            return self.fetch(for: fid)
        }
        
        return sprite
    }
}

extension Cache {
    func invalidate() {
        self.sprites.removeAll()
    }
}
