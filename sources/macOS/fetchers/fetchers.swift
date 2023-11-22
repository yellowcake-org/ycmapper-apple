//
//  fetchers.swift
//  ycmapper
//
//  Created by Alexander Orlov on 23.11.2023.
//

import Foundation

public struct Fetcher {
    public let map: URL
    public let root: URL
    
    public func sprite(at index: UInt16, for type: yc_res_pro_object_type_t) -> yc_res_frm_parse_result_t {
        let subpath = switch type {
        case YC_RES_PRO_OBJECT_TYPE_TILE: "ART/TILES/"
        default: fatalError()
        }
        
        let filename = switch type {
        case YC_RES_PRO_OBJECT_TYPE_TILE: "TILES.LST"
        default: fatalError()
        }
        
        var lst_result = yc_res_lst_parse_result_t(entries: nil)
        let lst_status = yc_res_lst_parse(
            self.root.appending(path: subpath.appending(filename)).path, withUnsafePointer(to: io_fs_api, { $0 }),
            &lst_result
        )
        
        assert(lst_status == YC_RES_LST_STATUS_OK)
        
        let entries = Array(
            UnsafeBufferPointer(
                start: lst_result.entries.pointee.pointers,
                count: lst_result.entries.pointee.count
            )
        )
        
        let frm_filename = root
            .appending(path: subpath)
            .appending(path: String(cString: entries[Int(index)].value)).path
        
        for var entry in entries { yc_res_lst_invalidate(&entry) }
        
        var frm_result = yc_res_frm_parse_result_t()
        let frm_status = yc_res_frm_parse(frm_filename, withUnsafePointer(to: io_fs_api, { $0 }), &frm_result)
        
        assert(frm_status == YC_RES_FRM_STATUS_OK)
        
        return frm_result
    }
    
    public func prototype(identifier pid: UInt32, for type: yc_res_pro_object_type_t) -> yc_res_pro_parse_result_t {
        let subpath = switch type {
        case YC_RES_PRO_OBJECT_TYPE_TILE: "PROTO/TILES/"
        case YC_RES_PRO_OBJECT_TYPE_ITEM: "PROTO/ITEMS/"
        case YC_RES_PRO_OBJECT_TYPE_SCENERY: "PROTO/SCENERY/"
        default: fatalError()
        }
        
        let filename = switch type {
        case YC_RES_PRO_OBJECT_TYPE_TILE: "TILES.LST"
        case YC_RES_PRO_OBJECT_TYPE_ITEM: "ITEMS.LST"
        case YC_RES_PRO_OBJECT_TYPE_SCENERY: "SCENERY.LST"
        default: fatalError()
        }
        
        var lst_result = yc_res_lst_parse_result_t(entries: nil)
        let lst_status = yc_res_lst_parse(
            root.appending(path: subpath.appending(filename)).path, withUnsafePointer(to: io_fs_api, { $0 }), &lst_result
        )
        
        assert(lst_status == YC_RES_LST_STATUS_OK)
        
        let index = yc_res_pro_index_from_object_id(pid) - 1
        let entries = Array(
            UnsafeBufferPointer(
                start: lst_result.entries.pointee.pointers,
                count: lst_result.entries.pointee.count
            )
        )
        
        let pro_filename = root
            .appending(path: subpath)
            .appending(path: String(cString: entries[Int(index)].value)).path
        
        for var entry in entries { yc_res_lst_invalidate(&entry) }
        
        var pro_result = yc_res_pro_parse_result_t(object: nil)
        let pro_status = yc_res_pro_parse(pro_filename, withUnsafePointer(to: io_fs_api, { $0 }), &pro_result)
        
        assert(pro_status == YC_RES_PRO_STATUS_OK)
        
        return pro_result
    }
    
    public func database() -> yc_vid_database_api_t {
        let result = yc_vid_database_api(
            context: withUnsafePointer(to: self, { .init(mutating: $0) }),
            fetch: { type, sprite_idx, result, ctx in
                guard let result = result
                else { return YC_VID_STATUS_INPUT }
                
                guard let ctx = ctx?.assumingMemoryBound(to: Self.self).pointee
                else { return YC_VID_STATUS_INPUT }
                
                let parsed = ctx.sprite(at: sprite_idx, for: type)
                result.pointee.frm.sprite = parsed.sprite
                
                // TODO: Find proper palette!
                let pal_status = yc_res_pal_parse(
                    ctx.root.appending(path: "COLOR.PAL").path,
                    withUnsafePointer(to: io_fs_api, { $0 }),
                    &result.pointee.pal
                )
                
                assert(YC_RES_PAL_STATUS_OK == pal_status)
                
                return YC_VID_STATUS_OK
            }
        )
        
        return result
    }
}
