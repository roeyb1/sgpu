// minimal build program which is required to link some stuff which lld cannot find on linux...

#run {
    set_build_options_dc(.{do_output = false});

    make_directory_if_it_does_not_exist("bin");

    compile_example("01_memory");
    compile_example("02_compute");
    compile_example("03_hello_square");
    compile_example("textures");

    copy_module_libraries_to_target("bin");
}

compile_example :: (name: string) {
    w := compiler_create_workspace(name);
    options := get_build_options();
    options.output_type = .EXECUTABLE;
    options.output_executable_name = name;
    options.output_path = "bin";

    if OS == .LINUX {
        compiler_add_library_search_directory(gcc_lib_dir());
    }

    set_build_options(options, w);

    add_build_file(tprint("%.jai", name), w);
}

gcc_lib_dir :: () -> string {
    #import "Process";
    #import "String";

    cmd: [] string = .["gcc", "-print-libgcc-file-name"];
    process_result, output_string, error_string, timeout_reached := run_command(..cmd, capture_and_return_output = true);

    return path_strip_filename(output_string);
}

copy_module_libraries_to_target :: (output_path: string) {
    dir_list :: (path: string, recursive := false) -> [] string {
        dirs: [..] string;

        visitor :: (info: *File_Visit_Info, user_data: *[..] string) {
            array_add(user_data, copy_string(info.full_name));
        }

        visit_files(path, recursive, *dirs, visitor, visit_files=false, visit_directories=true);
        return dirs;
    }

    push_allocator(temp);

    module_directories := dir_list("../modules", recursive=false);
    for module : module_directories {
        #if OS == {
            case .WINDOWS;
                os_name := "win";
                lib_ext := ".dll";
            case .MACOS;
                os_name := "mac";
                lib_ext := ".dylib";
            case .LINUX;
                os_name := "linux";
                lib_ext := ".so";
        }
        module_lib_dir_name := tprint("%/%", module, os_name);
        if is_directory(module_lib_dir_name) {

            module_binary_list := file_list(module_lib_dir_name);
            for binary : module_binary_list {
                if ends_with(binary, lib_ext) {
                    copy_file(binary, tprint("%/%", output_path, path_filename(binary)));
                }
            }
        }
    }
}

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
