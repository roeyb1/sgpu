// MIT License - Copyright (c) 2022 Hamad Almamari
// Tested with vulkan 1.0 and 1.2
// You can use this file to generate any version of vulkan bindings.
// You only need to set the vulkan.h and vulkan lib paths.
// Modified by Ryan Capote for Vulkan 1.3

// config
AT_COMPILE_TIME                 :: true;
VK_MEM_ALLOC_COMPILE            :: true;
VK_MEM_ALLOC_OUTPUT_BINDINGS    :: true;
vulkan_h_location               :: "source/vulkan/vulkan.h";

// if the lib path is empty system_library will be used.
#if OS == .WINDOWS {
    VULKAN_LIB_PATH :: "libs/win";
    OUTPUT_LIB_PATH :: "win/";
    GENERATED_FUNC_FILE :: "generated_funcs_windows.jai";
} else #if OS == .MACOS {
    VULKAN_LIB_PATH :: "libs/mac";
    OUTPUT_LIB_PATH :: "mac/";
    GENERATED_FUNC_FILE :: "generated_funcs_macos.jai";
} else #if OS == .LINUX {
    VULKAN_LIB_PATH :: "libs/linux";
    OUTPUT_LIB_PATH :: "linux/";
    GENERATED_FUNC_FILE :: "generated_funcs_linux.jai";
}

#if AT_COMPILE_TIME {
    #run {
        set_build_options_dc(.{do_output=false});
        if !generate() {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    #import "System";

    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        if !generate()
            exit(1);
    }
}

//--------------------

OMIT_LIST :: string.[
    // These are defined manually or not needed:
    "VK_NULL_HANDLE",
    "VK_TRUE",
    "VK_FALSE",
    "VK_WHOLE_SIZE",
    "VK_ATTACHMENT_UNUSED",
    "VK_QUEUE_FAMILY_IGNORED",
    "VK_REMAINING_ARRAY_LAYERS",
    "VK_REMAINING_MIP_LEVELS",
    "VK_SUBPASS_EXTERNAL",
    "VK_MAX_PHYSICAL_DEVICE_NAME_SIZE",
    "VK_UUID_SIZE",
    "VK_MAX_MEMORY_TYPES",
    "VK_MAX_MEMORY_HEAPS",
    "VK_MAX_EXTENSION_NAME_SIZE",
    "VK_MAX_DESCRIPTION_SIZE",
    // Vulkan 1.3 functions that exist on Linux but are not part of our Windows version:
    "vkGetPhysicalDeviceSurfaceCapabilities2KHR",
    "vkGetPhysicalDeviceSurfaceFormats2KHR",

    "VK_USE_PLATFORM_XLIB_KHR",
    "VK_USE_PLATFORM_WAYLAND_KHR",
    "VK_USE_PLATFORM_XCB_KHR",
    "VK_VERSION_1_0",
    
];

generate :: () -> bool {
    do_gen_bindings := ifx VK_MEM_ALLOC_COMPILE then compile_vulkan_memory_allocator() else true;
    if do_gen_bindings {
        return generate_bindings();
    } else {
        log("failed to compile vulkan memory allocator");
        return false;
    }
}

compile_vulkan_memory_allocator :: () -> bool {
    cwd := get_working_directory();
    include := tprint("-I%/source", cwd);
    src_path := tprint("%/source/vulkan_memory_allocator/vk_mem_alloc.cpp", cwd);
    success := true;
    extra_args: [..]string;

    #if OS == .WINDOWS {
        // vulkan memory allocator uses the VMA_CALL_PRE prefix before all of their functions
        // here we can seet them to be exported when it's compiled as a library.
        array_add(*extra_args, "/DVMA_CALL_PRE=__declspec(dllexport)");
        // without this, all implementations are erased before commpliation
        array_add(*extra_args, "/DVMA_IMPLEMENTATION");
        array_add(*extra_args, "/DNDEBUG");
    } else #if OS == .LINUX {
        array_add(*extra_args, "-DVMA_IMPLEMENTATION");
        array_add(*extra_args, "-DNDEBUG");
        array_add(*extra_args, "-fno-exceptions");
    } else #if OS == .MACOS {
        array_add(*extra_args, "-DVMA_IMPLEMENTATION");
        array_add(*extra_args, "-DNDEBUG");
        array_add(*extra_args, "-fno-exceptions");
    }

    // provide path to vulkan.h
    array_add(*extra_args, include);
    success &= build_cpp_static_lib(#run join(OUTPUT_LIB_PATH, "VkMemAlloc_DEBUG"), src_path, extra=extra_args, debug=true);
    success &= build_cpp_static_lib(#run join(OUTPUT_LIB_PATH, "VkMemAlloc"), src_path, extra=extra_args, debug=false);
    return success;
}

generate_bindings :: () -> bool {
    output_filename: string;
    opts:            Generate_Bindings_Options;
    {
        using opts;

        #if OS == .WINDOWS {
            array_add(*libnames, "vulkan-1");
            array_add(*extra_clang_arguments, "-x", "c", "-DWIN32_LEAN_AND_MEAN");
            array_add(*extra_clang_arguments, "-DVK_ENABLE_BETA_EXTENSIONS");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_WIN32_KHR");
            output_filename  = "generated_windows.jai";
        } else #if OS == .LINUX {
            array_add(*libraries, .{filename = "libvulkan"});
            array_add(*extra_clang_arguments, "-DVK_ENABLE_BETA_EXTENSIONS");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_XLIB_KHR");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_WAYLAND_KHR");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_XCB_KHR");
            output_filename  = "generated_linux.jai";
        } else #if OS == .MACOS {
            array_add(*libraries, .{ filename = "libvulkan" });

            array_add(*extra_clang_arguments, "-x", "c");
            array_add(*extra_clang_arguments, "-DVK_ENABLE_BETA_EXTENSIONS");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_METAL_EXT=1");
            array_add(*extra_clang_arguments, "-DVK_USE_PLATFORM_MACOS_MVK=1");

            output_filename = "generated_macos.jai";
        } else {
            assert(false);
        }

        if VULKAN_LIB_PATH then array_add(*library_search_paths, VULKAN_LIB_PATH);

        array_add(*source_files, vulkan_h_location);
        if VK_MEM_ALLOC_OUTPUT_BINDINGS {
            array_add(*source_files, "source/vulkan_memory_allocator/vk_mem_alloc.cpp");
            array_add(*libpaths, OUTPUT_LIB_PATH);
            array_add(*libnames, "VkMemAlloc");
        }

        generate_library_declarations = false;
        omit_global_declarations = false;
        will_print_bindings = () {
            // Change the library name to be the same on all platforms
            // so that we don't have to generate identical bindings for every platform just because the library name is different.
            context.generator.libraries[0].identifier = "libvulkan";
            generate_funcs();
        };

        visitor = vulkan_visitor;
        generate_compile_time_struct_checks = false;
        log_unsupported = true;
    }

    return generate_bindings(opts, output_filename);
}

available_flag_bits: Table(string, *Enum);
struct_type_decl: *Enum;

vulkan_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    // Omit header definitions (ex: VULKAN_H_)
    if decl.kind == .MACRO_DEFINITION && ends_with(decl.name, "_H_") {
        decl.decl_flags |= .OMIT_FROM_OUTPUT;
        return .STOP;
    }

    // Omit our OMIT_LIST
    if !parent_decl && array_find(OMIT_LIST, decl.name) {
        decl.decl_flags |= .OMIT_FROM_OUTPUT;
        return .STOP;
    }

    // ---- Function categorization for runtime loading ----
    // Keep VMA functions as direct #foreign (they link to vkmemalloc, not libvulkan).
    if decl.kind == .FUNCTION && begins_with(decl.name, "vma") {
        return .RECURSE;  // keep as #foreign vkmemalloc
    }
    if decl.type && decl.type.type_of_function {
        type := decl.type.type_of_function;
        if type.arguments.count > 0 && type.arguments[0].type.type_of_typedef {
            type_name := type.arguments[0].type.type_of_typedef.name;
            if (type_name == "VkDevice" || type_name == "VkQueue" || type_name == "VkCommandBuffer") && decl.name != "vkGetDeviceProcAddr" {
                array_add(*device_funcs, decl.name);
            } else if ((type_name == "VkInstance" || type_name == "VkPhysicalDevice") || decl.name == "vkGetDeviceProcAddr") && decl.name != "vkGetInstanceProcAddr" {
                array_add(*instance_funcs, decl.name);
            }
        }
        if decl.kind == .FUNCTION {
            // Omit #foreign libvulkan declaration — loaded at runtime instead.
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
        }
    }
    // Catch pre-instance functions exposed as PFN_ types.
    if decl.name == {
        case "PFN_vkCreateInstance"; #through;
        case "PFN_vkDebugUtilsMessengerCallbackEXT"; #through;
        case "PFN_vkDeviceMemoryReportCallbackEXT"; #through;
        case "PFN_vkEnumerateInstanceExtensionProperties"; #through;
        case "PFN_vkEnumerateInstanceLayerProperties"; #through;
        case "PFN_vkEnumerateInstanceVersion";
            array_add(*loader_funcs, slice(decl.name, 4, decl.name.count - 4));
    }

    if decl.kind == .ENUM {
        en := cast(*Enum)decl;
        if en.name == "VkStructureType"
            struct_type_decl = en; // Save for later

        // Almost all enums should be unsigned
        if en.type && decl.name != "VkResult" {
            if en.type.size == {
                case 1;
                    en.type = context.generator.type_def_u8;
                case 2;
                    en.type = context.generator.type_def_u16;
                case 4;
                    en.type = context.generator.type_def_u32;
                case 8;
                    en.type = context.generator.type_def_u64;
            }
        }

        if contains(decl.name, "FlagBits") {
            en.flags |= .IS_ENUM_FLAGS;
            en.flags |= .VALUES_IN_HEX;

            // Remember this so we can replace the generic VkFlags aliases with the actual enum_flag's type below. :VkFlags
            table_add(*available_flag_bits, decl.name, en);
        }
    }

    // Replace typedef which has "VkFlags" as value. :VkFlags
    // VkAccessFlags :: VkFlags   ->   VkAccessFlags :: VkAccessFlagBits;
    // We don't change the name of the FlagBits enum directly because both the ...FlagBits and the ...Flags aliases are used in declarations.
    if decl.kind == .TYPEDEF && decl.type.type_of_typedef &&  decl.type.type_of_typedef.name == "VkFlags" {
        //print("TYPEDEF(VkFlags):%\n", << decl.name);
        flags_name := replace(decl.name, "Flags", "FlagBits");
        found, enum_decl := table_find(*available_flag_bits, flags_name);
        if found {
            type := New(CType);
            type.type_of_enum = enum_decl;
            type.size         = enum_decl.type.size;
            decl.type         = type;
        }
    }

    // Set the default value for sType.
    if parent_decl && parent_decl.kind == .STRUCT && parent_decl.name != "VkBaseInStructure" && parent_decl.name != "VkBaseOutStructure" &&
    decl.kind == .DECLARATION && decl.name == "sType" {

        enum_value_name := get_sType_default_value_from_struct_name(parent_decl.name);

        // Vulkan has inconsisant naming for things, so the generator can't find these enum values because it splits or doesn't split
        // numbers correctly in newer cases. This manually changes the name of the enum so the generator can find it.
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_11_FEATURES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_1_FEATURES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_11_PROPERTIES" then enum_value_name  = "PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_12_FEATURES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_2_FEATURES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_12_PROPERTIES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_13_FEATURES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_3_FEATURES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_13_PROPERTIES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_14_FEATURES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_4_FEATURES";
        if enum_value_name == "PHYSICAL_DEVICE_VULKAN_14_PROPERTIES" then enum_value_name = "PHYSICAL_DEVICE_VULKAN_1_4_PROPERTIES";
        if enum_value_name == "PHYSICAL_DEVICE_TEXTURE_COMPRESSION_ASTCHDR_FEATURES" then enum_value_name = "PHYSICAL_DEVICE_TEXTURE_COMPRESSION_ASTC_HDR_FEATURES";
        if enum_value_name == "PHYSICAL_DEVICE_RGBA_10_X_6_FORMATS_FEATURES_EXT" then enum_value_name = "PHYSICAL_DEVICE_RGBA10X6_FORMATS_FEATURES_EXT";
        if enum_value_name == "PHYSICAL_DEVICE_IMAGE_2_D_VIEW_OF_3_D_FEATURES_EXT" then enum_value_name = "PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT";
        if enum_value_name == "PHYSICAL_DEVICE_IMAGE_SLICED_VIEW_OF_3_D_FEATURES_EXT" then enum_value_name = "PHYSICAL_DEVICE_IMAGE_SLICED_VIEW_OF_3D_FEATURES_EXT";
        if enum_value_name == "PHYSICAL_DEVICE_SHADER_64BIT_INDEXING_FEATURES_EXT" then enum_value_name = "PHYSICAL_DEVICE_SHADER_64_BIT_INDEXING_FEATURES_EXT";
        if enum_value_name == "D_3_D_12_FENCE_SUBMIT_INFO_KHR" then enum_value_name = "D3D12_FENCE_SUBMIT_INFO_KHR";
        if enum_value_name == "MAC_OS_SURFACE_CREATE_INFO_MVK" then enum_value_name = "MACOS_SURFACE_CREATE_INFO_MVK";

        enum_value: *Declaration;
        for struct_type_decl.enumerates {
            if it.output_name == enum_value_name {
                enum_value = it;
                break;
            }
        }
        assert(enum_value != null, "Could not find % enum value for \"%\" (%)", struct_type_decl.name, enum_value_name, decl.location);

        literal := New(Literal);
        literal.literal_kind = .ENUM;
        literal.enum_type = struct_type_decl;
        literal.enum_value = enum_value;
        decl.expression = literal;
    }

    return .RECURSE;
}

get_sType_default_value_from_struct_name :: (name: string) -> string {
    assert(name.count >= 3);

    is_upper :: (byte: u8) -> bool {
        if byte >= #char "A" && byte <= #char "Z" return true;
        return false;
    }

    is_num :: (byte: u8) -> bool {
        if byte >= #char "0" && byte <= #char "9" return true;
        return false;
    }

    builder: String_Builder;
    append(*builder, name[2]);
    for i: 3..name.count-1 {
        if is_upper(name[i]) {
            is_first_uppercase := !is_upper(name[i-1]);
            is_end_of_uppercase_word := (i != name.count-1 && !is_upper(name[i+1]) && !is_num(name[i+1]));
            is_bit_count := is_num(name[i-1]) && slice(name, i, 3) == "Bit";
            if (is_first_uppercase || is_end_of_uppercase_word) && !is_bit_count {
                append(*builder, #char "_");
            } else if (i >= 4 && slice(name, i-4, 4) == "AABB") { // Special case hack for names involing AABB
                append(*builder, #char "_");
            }
            append(*builder, name[i]);
        } else if is_num(name[i]) {
            if !is_num(name[i-1]) {

                // Here we check a bunch of special cases where a number should be after a letter without an underscore.
                skip_underscore := false;
                skip_underscore ||= slice(name, i-1, 3) == "H26"; // Special case for H264 and H265
                skip_underscore ||= slice(name, i-2, 2) == "AV"; // AV1
                skip_underscore ||= slice(name, i-2, 2) == "VP"; // VP9
                if i >= 4 {
                    skip_underscore ||= slice(name, i-4, 4) == "loat" && name[i] != "2"; // Bfloat and Float, but not float 2 features
                    skip_underscore ||= slice(name, i-4, 4) == "Uint";
                    skip_underscore ||= slice(name, i-3, 5) == "Win32";
                }
                skip_underscore ||= slice(name, i-3, 3) == "Int";
                if !skip_underscore {
                    append(*builder, #char "_");
                }
            }
            append(*builder, name[i]);
        } else {
            append(*builder, to_upper(name[i]));
        }
    }

    return builder_to_string(*builder);
}

// ---------------------------------------------------------------------------
// Runtime function pointer loading — generates generated_funcs_*.jai
// ---------------------------------------------------------------------------
device_funcs: [..] string;
instance_funcs: [..] string;
loader_funcs: [..] string;

generate_funcs :: () {
    builder: String_Builder;
    init_string_builder(*builder);

    write_func_variable_declaration :: (builder: *String_Builder, func_name: string) {
        append(builder, func_name);
        append(builder, ": PFN_");
        append(builder, func_name);
        append(builder, ";\n");
    }

    write_func_variable_assignment_device :: (builder: *String_Builder, func_name: string, prefix := "") {
        append(builder, prefix);
        append(builder, func_name);
        append(builder, " = xx vkGetDeviceProcAddr(device, \"");
        append(builder, func_name);
        append(builder, "\");\n");
    }
    write_func_variable_assignment_instance :: (builder: *String_Builder, func_name: string, prefix := "") {
        append(builder, prefix);
        append(builder, func_name);
        append(builder, " = xx vkGetInstanceProcAddr(instance, \"");
        append(builder, func_name);
        append(builder, "\");\n");
    }
    write_func_variable_assignment_loader :: (builder: *String_Builder, func_name: string, prefix := "") {
        append(builder, prefix);
        append(builder, func_name);
        append(builder, " = xx vkGetInstanceProcAddr(null, \"");
        append(builder, func_name);
        append(builder, "\");\n");
    }

    for loader_funcs { write_func_variable_declaration(*builder, it); }
    for instance_funcs { write_func_variable_declaration(*builder, it); }
    for device_funcs { write_func_variable_declaration(*builder, it); }

    append(*builder, "\n\nDevice_VTable :: struct {\n");
    for device_funcs {
        append(*builder, "    ");
        write_func_variable_declaration(*builder, it);
    }
    append(*builder, "}\n");

    append(*builder, "\nload_proc_addresses_vtable :: (device: VkDevice, vtable: *Device_VTable) {\n");
    for device_funcs { write_func_variable_assignment_device(*builder, it, "    vtable."); }
    append(*builder, "}\n");

    append(*builder, "\nload_device_proc_addresses :: (device: VkDevice) {\n");
    for device_funcs { write_func_variable_assignment_device(*builder, it, "    "); }
    append(*builder, "}\n");

    append(*builder, "\nload_instance_proc_addresses :: (instance: VkInstance) {\n");
    for instance_funcs { write_func_variable_assignment_instance(*builder, it, "    "); }
    for device_funcs { write_func_variable_assignment_instance(*builder, it, "    "); }
    append(*builder, "}\n");

    append(*builder, "\nload_global_proc_addresses :: () {\n\n");
    for loader_funcs { write_func_variable_assignment_loader(*builder, it, "    "); }
    append(*builder, "}\n");

    if GENERATED_FUNC_FILE == "" {
        log_error("GENERATED_FUNC_FILE not set for this platform");
        return;
    }
    success := write_entire_file(GENERATED_FUNC_FILE, *builder);
}

#scope_file
#import "Basic";
#import "Compiler";
#import "Check";
#import "Bindings_Generator";
#import "File";
#import "String";
#import "Hash_Table";
#import "BuildCpp";
