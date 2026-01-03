main :: () {
    result := gpu_init();
    defer gpu_shutdown();
    assert(result == .SUCCESS);

    COUNT :: 1024;

    // Create a buffer on the gpu which is visible and writeable by the cpu.
    // We can write to this buffer by directly writing to cpu memory via the returned pointer.
    // Allocating memory will also return the corresponding gpu pointer which will be used in gpu memory operations.
    // That pointer can be offset and modified as if it were just a regular *void.
    //
    // The DEFAULT memory type should be preferred for its ease of use when CPU->GPU transfers are required.
    staging_cpu, staging_gpu := gpu_malloc([COUNT] u8);
    assert(staging_cpu != null);
    defer gpu_free(staging_cpu);

    // Here we are allocating a buffer on the gpu which is only visible to the GPU.
    // There is no longer a CPU pointer here for us to write to. Only the GPU can
    // access the memory allocated in this way.
    //
    // The GPU memory type should be preferred when CPU->GPU transfers are not required as it is marginally
    // more efficient for the GPU and tends to be allocated in different heaps.
    _, gpu_ptr_a := gpu_malloc([COUNT] u8, .GPU);
    assert(gpu_ptr_a != 0);
    defer gpu_free(gpu_ptr_a);

    // Finally, we are allocating a READBACK style gpu
    //
    // The READBACK memory type should be used anytime the CPU will be reading back the results of GPU
    // computations frequently.
    readback_cpu, readback_gpu := gpu_malloc([COUNT] u8, .READBACK);
    assert(readback_cpu != null);
    defer gpu_free(readback_cpu);

    // Because we are writing to the mapped pointer, this operation will transparently write directly
    // into GPU memory.
    memset(staging_cpu, 255, COUNT);


    // SGPU provides 3 different types of GPU queues:
    // 1. 1x Main - this queue supports graphics operations, compute operations, and transfer operations. There is only one main queue.
    // 2. 4x Compute - these compute queues are required to support compute and transfer operations and there may be up to 4 of them.
    // 3. 2x Transfer - the transfer queues are only required to support transfer operations.
    //
    // The primary benefit of using different queues is that we can reduce pipeline stalls.
    // Transfer/compute operations can occur and depend on each other without blocking anything on the main queue.
    transfer_queue := gpu_get_queue(.TRANSFER, 0);
    result=, cmd_buff := gpu_start_command_recording(transfer_queue);
    assert(result == .SUCCESS);

    result = gpu_memcpy(cmd_buff, gpu_ptr_a, staging_gpu, COUNT);
    assert(result == .SUCCESS);

    // Insert a barrier here to ensure all previous transfer operations complete
    // before any subsequent transfer operations. Memcpy is a transfer operation.
    gpu_barrier(cmd_buff, .TRANSFER, .TRANSFER);

    result = gpu_memcpy(cmd_buff, readback_gpu, gpu_ptr_a, COUNT);
    assert(result == .SUCCESS);

    // GPU commands are asynchronous and above we only starting recording the commands.
    // Submit finally tells the GPU to start executing the batch of commands that have been
    // recorded to the command buffer.
    gpu_submit(cmd_buff);

    // Wait until all operations on the GPU have completed.
    // In a real environment the best way to do this would be to pass a "signal" semaphore to the submit command
    // and waiting on that. However since there is nothing else going on in the GPU right now this is going to be equivalent.
    gpu_wait_idle();

    // Just validate that all the data is now visible to the CPU.
    for 0..COUNT-1 {
        assert(readback_cpu.*[it] == 255);
    }
}

#import,file "../module.jai"(VALIDATION = true);
#import "Basic";
