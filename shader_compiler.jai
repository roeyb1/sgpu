#scope_export

compile_shader :: (shader_path: string, output_directory: string = "", debug_symbols: bool = false) -> bool, [] u8 {
    if !global_session then create_session();

    auto_release_temp();

    filename := shader_path;

    options: [..] slang.CompilerOptionEntry;
    options.allocator = temp;
    array_add(*options, .{
        slang.CompilerOptionName.Language, .{
            slang.CompilerOptionValueKind.String, 0, 0, "slang", null
        }
    });

    array_add(*options, .{
        slang.CompilerOptionName.Capability, .{
            slang.CompilerOptionValueKind.Int, xx slang.IGlobalSession_findCapability(global_session, "spirv_1_6"), 0, null, null
        }
    });
    array_add(*options, .{
        slang.CompilerOptionName.GLSLForceScalarLayout, .{
            slang.CompilerOptionValueKind.Int, 1, 0, null, null
        }
    });
    array_add(*options, .{
        slang.CompilerOptionName.VulkanInvertY, .{
            slang.CompilerOptionValueKind.Int, 1, 0, null, null
        }
    });

    if debug_symbols {
        array_add(*options, .{
            slang.CompilerOptionName.DebugInformation, .{
                slang.CompilerOptionValueKind.Int, 2, 0, null, null
            }
        });
    }

    target_desc := slang.TargetDesc.{
        format = .SLANG_SPIRV,
        profile = slang.IGlobalSession_findProfile(global_session, "sm_6_0"),
        forceGLSLScalarBufferLayout = true,
        flags = xx slang.SLANG_TARGET_FLAG.GENERATE_SPIRV_DIRECTLY,
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    source_dir := path_strip_filename(shader_path);
    search_paths := temp_c_string(source_dir);

    session_desc := slang.SessionDesc.{
        targets = *target_desc,
        targetCount = 1,
        defaultMatrixLayoutMode = .ROW_MAJOR,
        searchPaths = *search_paths,
        searchPathCount = 1,
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    session: *slang.ISession;
    slang.IGlobalSession_createSession(global_session, *session_desc, *session);
    if !session then return false, .[];
    defer slang.ISlangUnknown_release(session);

    diagnostic_blob: *slang.IBlob;
    slang_module := slang.ISession_loadModule(session, temp_c_string(shader_path), *diagnostic_blob);
    if diagnostic_blob then log_diagnostic_blob(diagnostic_blob);
    if !slang_module then return false, .{};

    entry_points: [..] *slang.IEntryPoint;
    entry_points.allocator = temp;
    {
        main := array_add(*entry_points);
        slang.IModule_findEntryPointByName(slang_module, "main", main);
    }

    components: [..] *slang.IComponentType;
    components.allocator = temp;
    array_add(*components, slang_module);
    for entry_points {
        array_add(*components, it);
    }

    composed_program: *slang.IComponentType;
    slang.ISession_createCompositeComponentType(session, components.data, components.count, *composed_program, *diagnostic_blob);
    if diagnostic_blob then log_diagnostic_blob(diagnostic_blob);
    if !composed_program then return false, .{};
    defer slang.ISlangUnknown_release(composed_program);

    linked_program: *slang.IComponentType;
    slang.IComponentType_link(composed_program, *linked_program);
    if diagnostic_blob then log_diagnostic_blob(diagnostic_blob);
    if !linked_program then return false, .{};

    spirv_code: *slang.IBlob;
    slang.IComponentType_getEntryPointCode(linked_program, 0, 0, *spirv_code, *diagnostic_blob);
    if diagnostic_blob then log_diagnostic_blob(diagnostic_blob);

    spirv_code_raw: [] u8 = NewArray(xx slang.ISlangBlob_getBufferSize(spirv_code), u8);

    memcpy(spirv_code_raw.data, slang.ISlangBlob_getBufferPointer(spirv_code), spirv_code_raw.count);

    slang.ISlangUnknown_release(spirv_code);

    if output_directory {
        output_path := tprint("%/%.spv", output_directory, path_strip_extension(filename));

        write_entire_file(output_path, spirv_code_raw.data, spirv_code_raw.count);
    }

    return true, spirv_code_raw;
}

#scope_file

log_diagnostic_blob :: (blob: *slang.IBlob) {
    diagnostic_string := string.{
        data = slang.ISlangBlob_getBufferPointer(blob),
        count = xx slang.ISlangBlob_getBufferSize(blob),
    };

    // #todo: how to pass shader compilation failures up to the user.
    log_error("%", diagnostic_string);

    slang.ISlangUnknown_release(blob);
}

create_session :: () {
    result := slang.slang_createGlobalSession(slang.SLANG_API_VERSION, *global_session);
    assert(slang.SLANG_SUCCEEDED(result));
}

global_session: *slang.IGlobalSession;

slang :: #import,file "modules/slang/module.jai";
#import "File";