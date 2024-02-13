//
//  fetchers.swift
//  ycmapper
//
//  Created by Alexander Orlov on 23.11.2023.
//

import Foundation

public class Fetcher {
    public enum Error: Swift.Error {
        case palette, index, proto, sprite, merge, recursion
    }
    
    public let map: URL
    public let root: URL
    
    init(map: URL, root: URL) {
        self.map = map
        self.root = root
    }
    
    public func sprite(
        fid: UInt32
    ) throws -> (yc_res_frm_parse_result_t, yc_res_pal_parse_result_t?) {
        var frm_result = yc_res_frm_parse_result_t()
        var pal_result: yc_res_pal_parse_result_t? = nil
        
        let type = yc_res_pro_object_type_from_fid(fid)
        let index = yc_res_pro_index_from_sprite_id(fid)
        
        let subpath = switch type {
        case YC_RES_PRO_OBJECT_TYPE_ITEM: "ART/ITEMS/"
        case YC_RES_PRO_OBJECT_TYPE_CRITTER: "ART/CRITTERS/"
        case YC_RES_PRO_OBJECT_TYPE_SCENERY: "ART/SCENERY/"
        case YC_RES_PRO_OBJECT_TYPE_WALL: "ART/WALLS/"
        case YC_RES_PRO_OBJECT_TYPE_TILE: "ART/TILES/"
        case YC_RES_PRO_OBJECT_TYPE_MISC: "ART/MISC/"
        case YC_RES_PRO_OBJECT_TYPE_INTERFACE: "ART/INTRFACE/"
        case YC_RES_PRO_OBJECT_TYPE_INVENTORY: "ART/INVEN/"
        case YC_RES_PRO_OBJECT_TYPE_HEAD: "ART/HEADS/"
        case YC_RES_PRO_OBJECT_TYPE_BACKGROUND: "ART/BACKGRND/"
        default: fatalError()
        }
        
        let filepath = self.root.appending(path: subpath)
        let pal_filename = URL(string: filepath.absoluteString)!
            .appendingPathExtension("PAL").path
        
        if FileManager.default.fileExists(atPath: pal_filename) {
            var palette = yc_res_pal_parse_result_t()
            let pal_status = yc_res_pal_parse(pal_filename, &io_fs_api, &palette)
            
            guard pal_status == YC_RES_PAL_STATUS_OK else { throw Error.palette }

            pal_result = palette
        }
        
        let lst_filename = switch type {
        case YC_RES_PRO_OBJECT_TYPE_ITEM: "ITEMS.LST"
        case YC_RES_PRO_OBJECT_TYPE_CRITTER: "CRITTERS.LST"
        case YC_RES_PRO_OBJECT_TYPE_SCENERY: "SCENERY.LST"
        case YC_RES_PRO_OBJECT_TYPE_WALL: "WALLS.LST"
        case YC_RES_PRO_OBJECT_TYPE_TILE: "TILES.LST"
        case YC_RES_PRO_OBJECT_TYPE_MISC: "MISC.LST"
        case YC_RES_PRO_OBJECT_TYPE_INTERFACE: "INTRFACE.LST"
        case YC_RES_PRO_OBJECT_TYPE_INVENTORY: "INVEN.LST"
        case YC_RES_PRO_OBJECT_TYPE_HEAD: "HEADS.LST"
        case YC_RES_PRO_OBJECT_TYPE_BACKGROUND: "BACKGRND.LST"
        default: fatalError()
        }
        
        var lst_result = yc_res_lst_entries_t()
        let lst_status = yc_res_lst_parse(
            self.root.appending(path: subpath.appending(lst_filename)).path, &io_fs_api,
            &lst_result
        )
        
        guard lst_status == YC_RES_LST_STATUS_OK else { throw Error.index }
        let entries = Array(UnsafeBufferPointer(start: lst_result.pointers, count: lst_result.count))
        
        if type == YC_RES_PRO_OBJECT_TYPE_CRITTER {
            func load(index: UInt32, recursed: Bool) throws {
                var suffix_ptr: UnsafeMutablePointer<UInt8>? = nil
                
                let pro_status = yc_res_pro_critter_sprite_suffix_from(fid, &suffix_ptr)
                guard pro_status == YC_RES_PRO_STATUS_OK else { throw Error.index }
                
                let suffix: String = suffix_ptr.flatMap({ String(cString: $0) }) ?? ""
                suffix_ptr?.deallocate()
                
                let entry = entries[Int(index)]
                let frm_filename = filepath.appending(
                    path: String(cString: entry.value).appending(suffix)
                )
                
                if yc_rec_pro_is_sprite_split(fid) {
                    var split: [yc_res_frm_parse_result_t] = .init(
                        repeating: yc_res_frm_parse_result_t(), count: Int(YC_RES_MATH_ORIENTATION_COUNT.rawValue)
                    )
                    
                    for idx in 0..<YC_RES_MATH_ORIENTATION_COUNT.rawValue {
                        let frm_complete_path = frm_filename.appendingPathExtension("FR\(idx)").path
                        
                        let frm_status = yc_res_frm_parse(
                            frm_complete_path, &io_fs_api, &split[Int(idx)]
                        )
                        
                        guard frm_status == YC_RES_FRM_STATUS_OK else { throw Error.sprite }
                    }
                    
                    var ptrs = split.map({ $0.sprite })
                    let merge_status = yc_res_frm_merge(
                        ptrs.withUnsafeMutableBufferPointer({ $0 }).baseAddress,
                        Int(YC_RES_MATH_ORIENTATION_COUNT.rawValue)
                    )
                    
                    guard merge_status == YC_RES_FRM_STATUS_OK else { throw Error.merge }
                    guard ptrs.count == 1 else { throw Error.merge }
                    
                    frm_result.sprite = ptrs.first!
                } else {
                    let frm_complete_path = frm_filename.appendingPathExtension("FRM").path
                    let frm_status = yc_res_frm_parse(frm_complete_path, &io_fs_api, &frm_result)
                    
                    if YC_RES_FRM_STATUS_OK != frm_status {
                        if recursed { throw Error.recursion }
                        else { try load(index: entry.index, recursed: true) }
                    }
                }
            }
            
            try load(index: UInt32(index), recursed: false)
        } else {
            let frm_complete_path = filepath.appending(path: String(cString: entries[Int(index)].value)).path
            let frm_status = yc_res_frm_parse(frm_complete_path, &io_fs_api, &frm_result)
            
            guard frm_status == YC_RES_FRM_STATUS_OK else { throw Error.sprite }
        }
        
        for var entry in entries { yc_res_lst_invalidate(&entry) }
        lst_result.pointers.deallocate()
        
        return (frm_result, pal_result)
    }
    
    public func prototype(identifier pid: UInt32, for type: yc_res_pro_object_type_t) throws -> yc_res_pro_parse_result_t {
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
        
        var lst_result = yc_res_lst_entries_t()
        let lst_status = yc_res_lst_parse(
            self.root.appending(path: subpath.appending(filename)).path, &io_fs_api, &lst_result
        )
        
        guard lst_status == YC_RES_LST_STATUS_OK else { throw Error.index }
        
        let index = yc_res_pro_index_from_object_id(pid) - 1
        let entries = Array(UnsafeBufferPointer(start: lst_result.pointers, count: lst_result.count))
        
        let pro_filename = self.root
            .appending(path: subpath)
            .appending(path: String(cString: entries[Int(index)].value)).path
        
        for var entry in entries { yc_res_lst_invalidate(&entry) }
        lst_result.pointers.deallocate()
        
        var pro_result = yc_res_pro_parse_result_t(object: nil)
        let pro_status = yc_res_pro_parse(pro_filename, &io_fs_api, &pro_result)
        
        guard pro_status == YC_RES_PRO_STATUS_OK else { throw Error.proto }
        
        return pro_result
    }
}
