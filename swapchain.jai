#scope_export

Native_Window_Type :: enum {
    UNKNOWN;
    WIN32;
    X11;
    WAYLAND;
}

gpu_init_swapchain :: (native_window: u64, window_type: Native_Window_Type) {
    native_window_handle = native_window;
    native_window_type = window_type;
    recreate_surface();

    // #todo: allow selecting present modes
    swapchain_present_mode = VkPresentModeKHR.IMMEDIATE_KHR;
    // #todo: allow selecting swapchain formats
    swapchain_format = .{VkFormat.B8G8R8A8_UNORM, .COLOR_SPACE_SRGB_NONLINEAR_KHR};

    supported_formats: [..] VkSurfaceFormatKHR;
    num_formats: u32;
    vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, *num_formats, null);
    array_resize(*supported_formats, num_formats);
    vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, *num_formats, supported_formats.data);

    recreate_swapchain();

    semaphore_create_info := VkSemaphoreCreateInfo.{
    };

    for 0..MAX_FRAMES_IN_FLIGHT-1 {
        vkCreateSemaphore(vk_device, *semaphore_create_info, null, *acquire_semaphores[it]);
        vkCreateSemaphore(vk_device, *semaphore_create_info, null, *present_semaphores[it]);
    }

    frame_timeline = gpu_create_semaphore(0);
}

gpu_swapchain_resize :: () {
    vkQueueWaitIdle(get_queue(gpu_get_queue(.MAIN, 0)).vk_queue);
    recreate_swapchain();
}

gpu_destroy_swapchain :: () {
    cleanup_swapchain_image_views();

    gpu_destroy_semaphore(frame_timeline);

    for acquire_semaphores {
        vkDestroySemaphore(vk_device, it, null);
    }
    for present_semaphores {
        vkDestroySemaphore(vk_device, it, null);
    }

    vkDestroySwapchainKHR(vk_device, vk_swapchain, null);
    destroy_surface();
}

gpu_swapchain_acquire :: () -> Gpu_Texture_View {
    wait_next_frame();

    acquire_semaphore_index = (frame_timeline_cpu + 1) % MAX_FRAMES_IN_FLIGHT;
    acquire_semaphore := acquire_semaphores[acquire_semaphore_index];
    vk_result := vkAcquireNextImageKHR(vk_device, vk_swapchain, U64_MAX, acquire_semaphore, null, *current_swapchain_index);
    if vk_result == .ERROR_OUT_OF_DATE_KHR || vk_result == .SUBOPTIMAL_KHR {
        gpu_swapchain_resize();
        vk_result = vkAcquireNextImageKHR(vk_device, vk_swapchain, U64_MAX, acquire_semaphore, null, *current_swapchain_index);
    }
    
    if vk_result == .SUCCESS {
        frame_timeline_cpu += 1;

        return swapchain_views[current_swapchain_index];
    }

    return 0;
}

gpu_present :: () {
    wait_semaphore := present_semaphores[current_swapchain_index];

    present_info := VkPresentInfoKHR.{
        waitSemaphoreCount = 1,
        pWaitSemaphores = *wait_semaphore,
        swapchainCount = 1,
        pSwapchains = *vk_swapchain,
        pImageIndices = *current_swapchain_index,
    };

    vk_result := vkQueuePresentKHR(get_queue(gpu_get_queue(.MAIN, 0)).vk_queue, *present_info);
    // resizes are handled during swapchain image acquisition so ignore these error codes here.
    assert(vk_result == .SUCCESS || vk_result == .SUBOPTIMAL_KHR || vk_result == .ERROR_OUT_OF_DATE_KHR);
}

gpu_submit_and_present :: (queue_handle: Gpu_Queue, buffer: Gpu_Command_Buffer) {
    assert(buffer != 0);
    index := (buffer - 1);
    assert(index < live_pools.count);
    pool := live_pools[index];

    image_barrier := VkImageMemoryBarrier2.{
        image = swapchain_images[current_swapchain_index],
        // Conservatively barrier on color attachment writes and transfer writes.
        srcStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        dstStageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
        srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT,
        subresourceRange = .{
            baseMipLevel = 0,
            baseArrayLayer = 0,
            levelCount = 1,
            layerCount = 1,
            aspectMask = get_image_aspect_mask(swapchain_format.format.(Format)),
        },
        oldLayout = .UNDEFINED,
        newLayout = .PRESENT_SRC_KHR,
    };

    dep_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier,
    };

    vkCmdPipelineBarrier2(pool.vk_cmd_buff, *dep_info);


    vkEndCommandBuffer(pool.vk_cmd_buff);

    queue := get_queue(queue_handle);

    queue_timeline_value := atomic_add(*queue.timeline_value, 1) + 1; // atomic_add returns the previous value.

    signal_values := u64.[queue_timeline_value, 0, 0];
    signal_semaphores := VkSemaphore.[queue.timeline, current_present_semaphore(), VK_NULL_HANDLE];
    signal_count: u32 = 3;

    vk_semaphore := get_semaphore(frame_timeline);
    signal_semaphores[2] = vk_semaphore;
    signal_values[2] = frame_timeline_cpu;

    timeline_info := VkTimelineSemaphoreSubmitInfo.{
        signalSemaphoreValueCount = signal_count,
        pSignalSemaphoreValues = signal_values.data,
    };

    wait_stages := VkPipelineStageFlagBits.TOP_OF_PIPE_BIT;
    wait_semaphore := current_acquire_semaphore();
    cmd_buffers := VkCommandBuffer.[pool.vk_cmd_buff];
    submit_info := VkSubmitInfo.{
        pNext = *timeline_info,
        commandBufferCount = cmd_buffers.count.(u32),
        pCommandBuffers = cmd_buffers.data,
        signalSemaphoreCount = signal_count,
        pSignalSemaphores = signal_semaphores.data,
        waitSemaphoreCount = 1,
        pWaitSemaphores = *wait_semaphore,
        pWaitDstStageMask = *wait_stages,
    };
    vkQueueSubmit(queue.vk_queue, 1, *submit_info, VK_NULL_HANDLE);

    live_pools[index] = null;
    array_add(*garbage_pools[queue.type], .{queue_timeline_value, pool});


    gpu_present();
}

gpu_frame_timeline :: () -> Gpu_Semaphore {
    return frame_timeline;
}

#scope_module

recreate_swapchain :: () {
    surface_capabilities: VkSurfaceCapabilitiesKHR;
    vk_result := vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, *surface_capabilities);
    assert_vk_result(vk_result);

    surface_extent = surface_capabilities.currentExtent;

    old_swapchain := vk_swapchain;

    cleanup_swapchain_image_views();

    create_info := VkSwapchainCreateInfoKHR.{
        surface = vk_surface,
        imageFormat = swapchain_format.format,
        imageColorSpace = swapchain_format.colorSpace,
        imageExtent = surface_extent,
        imageArrayLayers = 1,
        imageSharingMode = .EXCLUSIVE,
        imageUsage = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT,
        minImageCount = 3,
        queueFamilyIndexCount = 1,
        pQueueFamilyIndices = *get_queue(gpu_get_queue(.MAIN, 0)).vk_family,
        preTransform = .IDENTITY_BIT_KHR,
        compositeAlpha = .OPAQUE_BIT_KHR,
        presentMode = swapchain_present_mode,
        clipped = VK_TRUE,
        oldSwapchain = old_swapchain,
    };

    vk_result = vkCreateSwapchainKHR(vk_device, *create_info, null, *vk_swapchain);
    assert_vk_result(vk_result);

    if old_swapchain != VK_NULL_HANDLE {
        vkDestroySwapchainKHR(vk_device, old_swapchain, null);
    }

    image_count: u32;
    vk_result = vkGetSwapchainImagesKHR(vk_device, vk_swapchain, *image_count, null);
    assert_vk_result(vk_result);

    array_resize(*swapchain_images, image_count);
    array_resize(*swapchain_textures, image_count);
    array_resize(*swapchain_views, image_count);
    vk_result = vkGetSwapchainImagesKHR(vk_device, vk_swapchain, *image_count, swapchain_images.data);
    assert_vk_result(vk_result);

    view_desc := Gpu_View_Desc.{
        format = swapchain_format.format.(Format),
    };

    for swapchain_images {
        view_create_info := VkImageViewCreateInfo.{
            image = it,
            viewType = ._2D,
            format = swapchain_format.format,
            subresourceRange = .{
                aspectMask = get_image_aspect_mask(swapchain_format.format.(Format)),
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        };

        swapchain_textures[it_index] = pool_add(*live_textures, .{
            vk_image = it,
            desc = .{
                format = swapchain_format.format.(Format),
                usage = create_info.imageUsage.(Usage_Flags),
                dimensions = .[surface_extent.width, surface_extent.height, 1],
            },
        });

        view_handle := gpu_texture_view(swapchain_textures[it_index]);

        swapchain_views[it_index] = view_handle;
    }
}

create_surface :: () {
    #if OS == .WINDOWS {
        assert(native_window_type == .WIN32);

        create_info := VkWin32SurfaceCreateInfoKHR.{
            hinstance = GetModuleHandleA(null),
            hwnd = native_window_handle.(HWND),
        };
        if !vkCreateWin32SurfaceKHR {
            vkCreateWin32SurfaceKHR = cast(PFN_vkCreateWin32SurfaceKHR) vkGetInstanceProcAddr(vk_instance, "vkCreateWin32SurfaceKHR");
        }
        vk_result := vkCreateWin32SurfaceKHR(vk_instance, *create_info, null, *vk_surface);
        assert(vk_result);
    } else #if OS == .LINUX {
        if native_window_type == .WAYLAND {
            assert(false, "todo");
        } else if native_window_type == .X11 {
            create_info := VkXlibSurfaceCreateInfoKHR.{
                display = XOpenDisplay(null),
                window = native_window_handle.(Window)
            };

            if !vkCreateXlibSurfaceKHR {
                vkCreateXlibSurfaceKHR = cast(PFN_vkCreateXlibSurfaceKHR) vkGetInstanceProcAddr(vk_instance, "vkCreateXlibSurfaceKHR");
            }
            vk_result := vkCreateXlibSurfaceKHR(vk_instance, *create_info, null, *vk_surface);
            assert_vk_result(vk_result);
        }
    } else {
        assert(false, "swapchain creation unvaiable on this OS");
    }
}

destroy_surface :: () {
    vkDestroySurfaceKHR(vk_instance, vk_surface, null);
    vk_surface = VK_NULL_HANDLE;
}

recreate_surface :: () {
    destroy_surface();
    create_surface();
}

cleanup_swapchain_image_views :: () {
    for swapchain_textures {
        gpu_free(it);
    }
}


wait_next_frame :: () {
    if frame_timeline_cpu > MAX_FRAMES_IN_FLIGHT {
        gpu_wait_semaphore(frame_timeline, frame_timeline_cpu - MAX_FRAMES_IN_FLIGHT);
    }
}

current_present_semaphore :: () -> VkSemaphore {
    return present_semaphores[current_swapchain_index];
}
current_acquire_semaphore :: () -> VkSemaphore {
    return acquire_semaphores[acquire_semaphore_index];
}

native_window_handle: u64;
native_window_type: Native_Window_Type;
vk_surface: VkSurfaceKHR;
surface_extent: VkExtent2D;

swapchain_present_mode: VkPresentModeKHR;
swapchain_format: VkSurfaceFormatKHR;

vk_swapchain: VkSwapchainKHR;

// #todo: expose this to the module parameters?
// #todo: support more than one frame in flight.
MAX_FRAMES_IN_FLIGHT :: 3;

acquire_semaphores: [MAX_FRAMES_IN_FLIGHT] VkSemaphore;
present_semaphores: [MAX_FRAMES_IN_FLIGHT] VkSemaphore;

frame_timeline: Gpu_Semaphore;
frame_timeline_cpu: u64;

swapchain_images: [..] VkImage;
swapchain_textures: [..] Gpu_Texture;
swapchain_views: [..] Gpu_Texture_View;
current_swapchain_index: u32;
acquire_semaphore_index: u64;

#if OS == .WINDOWS {
    #import "Windows";

    vkCreateWin32SurfaceKHR: PFN_vkCreateWin32SurfaceKHR;
} else #if OS == .LINUX {
    #import "X11";
    vkCreateXlibSurfaceKHR: PFN_vkCreateXlibSurfaceKHR;
}