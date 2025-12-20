// minimal build program which is required to link some stuff which lld cannot find on linux...

#run {
    set_build_options_dc(.{do_output = false});

    make_directory_if_it_does_not_exist("bin");

    compile_example("basic");
    compile_example("instanced_drawing");
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

#import "Basic";
#import "Compiler";
#import "File";