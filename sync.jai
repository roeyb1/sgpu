#scope_export

Gpu_Timeline_Pair :: struct {
    semaphore: Gpu_Semaphore;
    value: u64;
}

gpu_create_semaphore :: (initial: u64) -> Gpu_Semaphore {
    timeline_create_info := VkSemaphoreTypeCreateInfo.{
        semaphoreType = .TIMELINE,
        initialValue = initial,
    };
    create_info := VkSemaphoreCreateInfo.{
        pNext = *timeline_create_info,
    };

    vk_semaphore: VkSemaphore;
    vk_result := vkCreateSemaphore(vk_device, *create_info, null, *vk_semaphore);
    if vk_result != .SUCCESS {
        return 0;
    }

    handle := pool_add(*live_semaphores, .{vk_semaphore});
    if handle == 0 {
        log_error("Exceeded semaphore allocation capacity (%)!", live_semaphores.max);
        return 0;
    }

    return handle;
}

gpu_wait_semaphore :: (timeline: Gpu_Timeline_Pair) {
    semaphore := pool_get(live_semaphores, timeline.semaphore);

    wait_info := VkSemaphoreWaitInfo.{
        semaphoreCount = 1,
        pSemaphores = *semaphore.vk_semaphore,
        pValues = *timeline.value,
    };
    vk_result := vkWaitSemaphores(vk_device, *wait_info, U64_MAX);
    assert_vk_result(vk_result);
}

gpu_destroy_semaphore :: (semaphore_handle: Gpu_Semaphore) {
    removed, semaphore := pool_remove(*live_semaphores, semaphore_handle);
    if removed {
        vkDestroySemaphore(vk_device, semaphore.vk_semaphore, null);
    }
}

#scope_module

Semaphore :: struct {
    vk_semaphore: VkSemaphore;
}

get_semaphore :: (semaphore_handle: Gpu_Semaphore) -> *Semaphore {
    semaphore := pool_get(live_semaphores, semaphore_handle);
    return semaphore;
}

live_semaphores: Pool(Gpu_Semaphore, Semaphore);
