#scope_export

// Shader_VFS — virtual filesystem implementing ISlangFileSystem.
//
// Pass to compile_shader() via file_system parameter to resolve
// #include / import directives from in-memory sources instead of disk.
//
// Usage:
//   load_src :: (path: string) -> string { 
//        return get_asset(path); // Some callback that return a shader code by it's path. 
//                                // It can be called with non-existant paths due to explorative nature of the slang compiler!
//   }
//   vfs := make_shader_vfs(load_src);
//   defer cleanup_shader_vfs(vfs);
//   ok, spirv := compile_shader("main.slang", "", false, vfs);

Load_Callback :: #type (path: string) -> string;

// ---- Shader_VFS (implements ISlangFileSystem) ----

// Shader_VFS layout (must match ISlangFileSystem at offset 0):
//   offset 0: vtable ptr (ISlangFileSystem_VTable*)
//   offset 8: callback (Load_Callback)
//  offset 16: refcount (u32)

Shader_VFS :: struct {
    vtable: *slang.ISlangFileSystem_VTable;  // COM-compatible at offset 0
    callback: Load_Callback;
    refcount: u32;
}

make_shader_vfs :: (callback: Load_Callback) -> *Shader_VFS {
    vfs := New(Shader_VFS);
    vfs.vtable = get_vfs_vtable();
    vfs.callback = callback;
    vfs.refcount = 1;
    return vfs;
}

cleanup_shader_vfs :: (vfs: *Shader_VFS) {
    free(vfs);
}

#scope_file

// ---- Shader_File_Blob (implements ISlangBlob) ----

// Shader_File_Blob layout:
//   offset 0: vtable ptr (ISlangBlob_VTable*)
//   offset 8: data (*u8)
//  offset 16: size (u64)
//  offset 24: refcount (u32)

Shader_File_Blob :: struct {
    vtable: *slang.ISlangBlob_VTable;
    data: *u8;
    size: u64;
    refcount: u32;
}

// ---- VFS vtable functions ----

vfs_query_interface :: (this: *slang.ISlangUnknown, uuid: *slang.SlangUUID, outObject: **void) -> slang.SlangResult #cpp_method {
    outObject.* = null;
    return VFS_E_NO_INTERFACE;
}

vfs_add_ref :: (this: *slang.ISlangUnknown) -> u32 #cpp_method {
    refcount_ptr: *u32 = cast(*u32, cast(*u8, this) + 16);
    refcount_ptr.* += 1;
    return refcount_ptr.*;
}

vfs_release :: (this: *slang.ISlangUnknown) -> u32 #cpp_method {
    refcount_ptr: *u32 = cast(*u32, cast(*u8, this) + 16);
    refcount_ptr.* -= 1;
    return refcount_ptr.*;
}

vfs_cast_as :: (this: *slang.ISlangCastable, guid: *slang.SlangUUID) -> *void #cpp_method {
    return null;
}

vfs_load_file :: (this: *slang.ISlangFileSystem, path: *u8, outBlob: **slang.ISlangBlob) -> slang.SlangResult #cpp_method {
    vfs_ctx: #Context;
    push_context vfs_ctx {
        vfs := cast(*Shader_VFS)this;
        path_str := to_string(path);

        source := vfs.callback(path_str);

        if source.count == 0 {
            return VFS_E_NOT_FOUND;
        }

        blob_struct_size := size_of(Shader_File_Blob);
        total_size := blob_struct_size + source.count;
        mem := cast(*u8, alloc(total_size));

        blob := cast(*Shader_File_Blob, mem);
        blob.vtable = get_blob_vtable();
        blob.refcount = 1;

        data_ptr := mem + blob_struct_size;
        memcpy(data_ptr, source.data, source.count);
        blob.data = data_ptr;
        blob.size = cast(u64, source.count);

        free(source.data);  // callback-owned data, copied into blob

        outBlob.* = xx blob;

        return VFS_OK;
    }
}

// ---- Blob vtable functions ----

blob_query_interface :: (this: *slang.ISlangUnknown, uuid: *slang.SlangUUID, outObject: **void) -> slang.SlangResult {
    return VFS_E_NO_INTERFACE;
}

blob_add_ref :: (this: *slang.ISlangUnknown) -> u32 #cpp_method {
    blob: *Shader_File_Blob = xx this;
    blob.refcount += 1;
    return blob.refcount;
}

blob_release :: (this: *slang.ISlangUnknown) -> u32 #cpp_method {
    ctx: #Context;
    push_context ctx {
        blob: *Shader_File_Blob = xx this;
        blob.refcount -= 1;
        if blob.refcount == 0 {
            free(blob);
            return 0;
        }
        return blob.refcount;
    }
}

blob_get_buffer_pointer :: (this: *slang.ISlangBlob) -> *void #cpp_method {
    blob: *Shader_File_Blob = xx this;
    return blob.data;
}

blob_get_buffer_size :: (this: *slang.ISlangBlob) -> u64 #cpp_method {
    blob: *Shader_File_Blob = xx this;
    return blob.size;
}

// ---- Static vtables ----

VFS_OK               : slang.SlangResult = 0;   // SLANG_OK
VFS_E_NOT_FOUND      : slang.SlangResult = -5;  // SLANG_E_NOT_FOUND
VFS_E_NO_INTERFACE   : slang.SlangResult = -1;  // SLANG_E_NO_INTERFACE

vfs_vtable_cache: *slang.ISlangFileSystem_VTable;
blob_vtable_cache: *slang.ISlangBlob_VTable;

get_vfs_vtable :: () -> *slang.ISlangFileSystem_VTable {
    if vfs_vtable_cache == null {
        vfs_vtable_cache = New(slang.ISlangFileSystem_VTable);
        vfs_vtable_cache.queryInterface = vfs_query_interface;
        vfs_vtable_cache.addRef         = vfs_add_ref;
        vfs_vtable_cache.release        = vfs_release;
        vfs_vtable_cache.castAs         = vfs_cast_as;
        vfs_vtable_cache.loadFile       = vfs_load_file;
    }
    return vfs_vtable_cache;
}

get_blob_vtable :: () -> *slang.ISlangBlob_VTable {
    if blob_vtable_cache == null {
        blob_vtable_cache = New(slang.ISlangBlob_VTable);
        blob_vtable_cache.queryInterface   = xx blob_query_interface;
        blob_vtable_cache.addRef           = xx blob_add_ref;
        blob_vtable_cache.release          = xx blob_release;
        blob_vtable_cache.getBufferPointer = xx blob_get_buffer_pointer;
        blob_vtable_cache.getBufferSize    = xx blob_get_buffer_size;
    }
    return blob_vtable_cache;
}
