main :: () {
    result := gpu_init();
    defer gpu_shutdown();
    assert(result == .SUCCESS);

    COUNT :: 1024;

    buffer_cpu, buffer_gpu := gpu_malloc([COUNT] float);
    assert(buffer_cpu != null);
    defer gpu_free(buffer_cpu);

    for 0..COUNT-1 {
        buffer_cpu.*[it] = 0.0;
    }

    // Raw precompiled spirv can be passed to `gpu_create_compute_pipeline`
    // or the included slang shader compiler can be used to compile slang shaders.
    success, spirv := compile_shader("../shaders/compute.slang");
    assert(success);
    pipeline := gpu_create_compute_pipeline(spirv);
    defer gpu_free_pipeline(pipeline);

    // We will use the dedicated compute queue here but we could also use the MAIN queue.
    // It is required to support compute operations as well as graphics
    compute_queue := gpu_get_queue(.COMPUTE, 0);
    result=, cmd_buff := gpu_start_command_recording(compute_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, pipeline);
    assert(result == .SUCCESS);

    // All shaders invocations in SGPU take as input a pointer to a block of user allocated memory.
    // That memory can be a block of parameters or it can be data to mutate. Entirely up to the programmer.
    // If the shader has no parameters, it is fine to pass null or 0 to those arguments.
    //
    // A common pattern is to use an arena allocator to push parameter structs into gpu memory.
    // See later samples for examples of this.
    //
    // In this case, the output data pointer is simply passed to the shader as this user_data ptr so it can write to it.
    gpu_dispatch(cmd_buff, buffer_gpu, .[(COUNT + 63) / 64, 1, 1]);

    gpu_submit(cmd_buff);

    gpu_wait_idle();

    for 0..COUNT-1 {
        assert(buffer_cpu.*[it] == 1.0);
    }
}

#import,file "../module.jai"(VALIDATION = true);
#import "Basic";
