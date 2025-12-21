main :: () {
    gpu_init();

    transfer_queue := gpu_get_queue(.TRANSFER, 0);

    {
        count :: 1024;
        ptr, staging_ptr := gpu_malloc([count] u8);
        _, gpu_ptr_a := gpu_malloc([count] u8, .GPU);
        _, gpu_ptr_b := gpu_malloc([count] u8, .GPU);

        memset(ptr, 255, count);

        for 0..count-1 {
            assert(ptr.*[it] == 255);
        }

        cmd_buff := gpu_start_command_recording(transfer_queue);

        gpu_memcpy(cmd_buff, gpu_ptr_a, staging_ptr, count);
        gpu_barrier(cmd_buff, .TRANSFER, .TRANSFER);
        gpu_memcpy(cmd_buff, gpu_ptr_b, gpu_ptr_a, count);
        gpu_barrier(cmd_buff, .TRANSFER, .TRANSFER);
        gpu_memcpy(cmd_buff, staging_ptr, gpu_ptr_b, count);


        gpu_submit(transfer_queue, cmd_buff);

        gpu_wait_idle();

        // ensures that the barriers sufficiently prevented read after write and write racing write hazards.
        // this works at least on my hardware
        for 0..count-1 {
            assert(ptr.*[it] == 255);
        }

        gpu_free(ptr);
        gpu_free(gpu_ptr_a);
        gpu_free(gpu_ptr_b);
    }

    {
        semaphore := gpu_create_semaphore(0);

        gpu_wait_semaphore(semaphore, 0);
        gpu_destroy_semaphore(semaphore);
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    c1_queue := gpu_get_queue(.COMPUTE, 0);
    c2_queue := gpu_get_queue(.COMPUTE, 1);

    for 0..200 {
        for 0..127 {
            cmd_buff := gpu_start_command_recording(main_queue);

            gpu_submit(main_queue, cmd_buff);

            cmd_buff = gpu_start_command_recording(c1_queue);
            gpu_submit(c1_queue, cmd_buff);

            cmd_buff = gpu_start_command_recording(c2_queue);
            gpu_submit(c1_queue, cmd_buff);
        }

        gpu_wait_idle();
    }

    gpu_shutdown();
}

#import,file "../../simp_gpu/module.jai"(VALIDATION = true);
#import "Basic";

