SLANG_SRC_PATH :: "lib/include";

#run generate_bindings();

generate_bindings :: () -> bool {
    set_build_options_dc(.{ do_output=false });

    output_filename: string;
    opts: Generate_Bindings_Options;
    {
        using opts;

        if OS == {
            case .WINDOWS; output_filename = "windows.jai";
            case .LINUX; output_filename = "linux.jai";
        }

        if OS == {
            case .WINDOWS; array_add(*libpaths, "./lib/win");
            case .LINUX; array_add(*libpaths, "./lib/linux");
        }

        if OS == {
            case .WINDOWS; array_add(*libnames, "slang-compiler");
            case .LINUX; array_add(*libnames, "libslang");
        }

        array_add(*source_files, tprint("%/slang.h", SLANG_SRC_PATH));

        array_add(*flatten_namespaces, "slang");

        array_add(*extra_clang_arguments, "-x", "c++");
        #if OS == .WINDOWS {
            array_add(*extra_clang_arguments, "-DWIN32_LEAN_AND_MEAN");
        }

        mimic_spacing_flags &= ~(Mimic_Spacing_Flags.VTABLE);
        log_stripped_declarations = false;
        // generate_compile_time_struct_checks = false;

        generate_library_declarations=false;
        visitor=slang_visitor;

        header = SLANG_RESULT_HELPERS;
    }

    return generate_bindings(opts, output_filename);
}

#scope_file

slang_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> result: Declaration_Visit_Result = .RECURSE {
    // This is being set to an invalid `~u64(0)`, so manually setting it to `U64_MAX` to make it unbounded.
    if decl.name == "SLANG_UNBOUNDED_SIZE" {
        literal := cast(*Literal) decl.expression;
        literal.raw_value = tprint("%", U64_MAX);
    }

    return;
}

#import "Basic";
#import "Math";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "String";

SLANG_RESULT_HELPERS :: #string __slang_header

// Slang Result helpers and macro-defined constants

SLANG_FAILED :: (status: s32) -> bool {
    return status < 0;
}

SLANG_SUCCEEDED :: (status: s32) -> bool {
    return status >= 0;
}

SLANG_GET_RESULT_FACILITY :: (r: s32) -> s32 {
    return (r >> 16) & 0x7fff;
}

SLANG_GET_RESULT_CODE :: (r: s32) -> s32 {
    return r & 0xffff;
}

SLANG_MAKE_ERROR :: (fac: s32, code: s32) -> s32 {
    return (fac << 16) | code | cast(s32, 0x80000000);
}

SLANG_MAKE_SUCCESS :: (fac: s32, code: s32) -> s32 {
    return (fac << 16) | cast(s32, code);
}

SLANG_FAIL :: #run SLANG_MAKE_ERROR(SLANG_FACILITY_WIN_GENERAL, 0x4005);

SLANG_MAKE_WIN_GENERAL_ERROR :: (code: s32) -> s32 {
    return SLANG_MAKE_ERROR(SLANG_FACILITY_WIN_GENERAL, code);
}

SLANG_E_NOT_IMPLEMENTED :: #run SLANG_MAKE_WIN_GENERAL_ERROR(0x4001);
SLANG_E_NO_INTERFACE    :: #run SLANG_MAKE_WIN_GENERAL_ERROR(0x4002);
SLANG_E_ABORT           :: #run SLANG_MAKE_WIN_GENERAL_ERROR(0x4004);

SLANG_E_INVALID_HANDLE :: #run SLANG_MAKE_ERROR(SLANG_FACILITY_WIN_API, 6);
SLANG_E_INVALID_ARG    :: #run SLANG_MAKE_ERROR(SLANG_FACILITY_WIN_API, 0x57);
SLANG_E_OUT_OF_MEMORY  :: #run SLANG_MAKE_ERROR(SLANG_FACILITY_WIN_API, 0xe);

SLANG_MAKE_CORE_ERROR :: (code: s32) -> s32 {
    return SLANG_MAKE_ERROR(SLANG_FACILITY_CORE, code);
}

SLANG_E_BUFFER_TOO_SMALL :: #run SLANG_MAKE_CORE_ERROR(1);
SLANG_E_UNINITIALIZED    :: #run SLANG_MAKE_CORE_ERROR(2);
SLANG_E_PENDING          :: #run SLANG_MAKE_CORE_ERROR(3);
SLANG_E_CANNOT_OPEN      :: #run SLANG_MAKE_CORE_ERROR(4);
SLANG_E_NOT_FOUND        :: #run SLANG_MAKE_CORE_ERROR(5);
SLANG_E_INTERNAL_FAIL    :: #run SLANG_MAKE_CORE_ERROR(6);
SLANG_E_NOT_AVAILABLE    :: #run SLANG_MAKE_CORE_ERROR(7);
SLANG_E_TIME_OUT         :: #run SLANG_MAKE_CORE_ERROR(8);
__slang_header;
