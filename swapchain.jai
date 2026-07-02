#scope_export

Native_Window_Type :: enum {
    UNKNOWN;
    WIN32;
    X11;
    WAYLAND;
    COCOA;
}

Present_Mode :: enum {
    IMMEDIATE    :: 0;
    MAILBOX      :: 1;
    FIFO         :: 2;
    FIFO_RELAXED :: 3;
}

// What the user requested during swapchain creation
preferred_min_image_count: u32;

// min_image_count refers to the preferred swapchain image count, commonly this is 2 for double buffering or 3 for
// triple buffering. NOTE: The actual image count used will depend on what the platform supports and which present mode
// is selected. For more details, see https://docs.vulkan.org/samples/latest/samples/performance/swapchain_images/README.html
gpu_init_swapchain :: (native_window: u64, window_type: Native_Window_Type, preferred_present_modes: [] Present_Mode = .[], preferred_formats: [] Format = .[], min_image_count: u32 = 3) {
    preferred_min_image_count = min_image_count;

    native_window_handle = native_window;
    native_window_type = window_type;
    recreate_surface();

    swapchain_present_mode = select_present_mode(preferred_present_modes);
    swapchain_format = select_format(preferred_formats);

    recreate_swapchain();

    semaphore_create_info := VkSemaphoreCreateInfo.{
    };

    assert(acquire_semaphores.count == 0 && swapchain_images.count > 0);
    array_resize(*acquire_semaphores, swapchain_images.count);
    for * acquire_semaphores {
        vk_result := vkCreateSemaphore(vk_device, *semaphore_create_info, null, it);
        assert_vk_result(vk_result);
    }

    assert(present_semaphores.count == 0 && swapchain_images.count > 0);
    array_resize(*present_semaphores, swapchain_images.count);
    for * present_semaphores {
        vk_result := vkCreateSemaphore(vk_device, *semaphore_create_info, null, it);
        assert_vk_result(vk_result);
    }

    gpu_init_timestamps(swapchain_images.count);

    gpu_frame_timeline = gpu_create_semaphore(0);
    assert(gpu_frame_timeline != 0);
}

gpu_swapchain_resize :: () {
    vkQueueWaitIdle(get_queue(gpu_get_queue(.MAIN, 0)).vk_queue);
    recreate_swapchain();

    // recreate_swapchain bypasses semaphore creation/destruction, yet it may adjust
    // the swapchain_images count. let's make sure these sizes don't unexpectedly drift
    debug_assert(acquire_semaphores.count == swapchain_images.count);
    debug_assert(acquire_semaphores.count == present_semaphores.count);
}

gpu_get_surface_extent :: () -> u32, u32 {
    return surface_extent.width, surface_extent.height;
}

gpu_destroy_swapchain :: () {
    cleanup_swapchain_image_views();

    ok := gpu_destroy_semaphore(gpu_frame_timeline);
    debug_assert(ok, "Failed to destroy gpu_frame_timeline semaphore");
    gpu_frame_timeline = 0;

    for acquire_semaphores {
        vkDestroySemaphore(vk_device, it, null);
    }
    array_reset(*acquire_semaphores);

    for present_semaphores {
        vkDestroySemaphore(vk_device, it, null);
    }
    array_reset(*present_semaphores);

    vkDestroySwapchainKHR(vk_device, vk_swapchain, null);
    vk_swapchain = VK_NULL_HANDLE;
    destroy_surface();

    gpu_destroy_timestamps();

    // reset global counters, else a swapchain recreation (as would occur when toggling vsync), 
    // would use stale/incorrect values on semaphore waits
    current_swapchain_index = 0;
    cpu_frame_timeline = 0;

    preferred_min_image_count = 0;
}

gpu_swapchain_acquire :: () -> Gpu_Result, Gpu_Texture_View {
    wait_next_frame();

    acquire_semaphore_index = (cpu_frame_timeline + 1) % acquire_semaphores.count.(u64);
    acquire_semaphore := acquire_semaphores[acquire_semaphore_index];
    assert(acquire_semaphore != VK_NULL_HANDLE);
    vk_result := vkAcquireNextImageKHR(vk_device, vk_swapchain, U64_MAX, acquire_semaphore, null, *current_swapchain_index);

    if vk_result == .SUCCESS {
        cpu_frame_timeline += 1;

        queue_handle := gpu_get_queue(.MAIN, 0);
        result, cmd_buff := gpu_start_command_recording(queue_handle);
        if result != .SUCCESS {
            cpu_frame_timeline -= 1;
            return result, 0;
        }

        timestamps_reset(cmd_buff);

        transition_swapchain_to_general(cmd_buff);

        submit_command_buffer(.{
            cmd_buff = cmd_buff,
            wait_semaphores = .[acquire_semaphore],
        });

        return .SUCCESS, swapchain_views[current_swapchain_index];
    }

    // #todo: this is not actually a success. acquire next image can return out of date and suboptimal which we
    // return as succeses but with invalid texture handles. This needs to be updated
    return .SUCCESS, 0;
}

gpu_present :: () {
    wait_semaphore := present_semaphores[current_swapchain_index];
    assert(wait_semaphore != VK_NULL_HANDLE);

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

gpu_submit_and_present :: (cmd_buff: Gpu_Command_Buffer, signals: [] Gpu_Timeline_Pair = .[], waits: [] Gpu_Timeline_Pair = .[]) {
    vk_cmd_buff := get_cmd_buff(cmd_buff);

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
        oldLayout = .GENERAL,
        newLayout = .PRESENT_SRC_KHR,
    };

    dep_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier,
    };

    vkCmdPipelineBarrier2(vk_cmd_buff, *dep_info);

    signal_timelines: [..] Gpu_Timeline_Pair;
    signal_timelines.allocator = temp;
    wait_timelines: [..] Gpu_Timeline_Pair;
    wait_timelines.allocator = temp;

    array_add(*signal_timelines, .{gpu_frame_timeline, cpu_frame_timeline});
    for signals {
        array_add(*signal_timelines, it);
    }
    for waits {
        array_add(*wait_timelines, it);
    }

    submit_command_buffer(.{
        cmd_buff = cmd_buff,
        signal_semaphores = .[current_present_semaphore()],
        signal_timelines = signal_timelines,
        wait_timelines = wait_timelines,
    });

    gpu_present();
}

gpu_get_frame_timeline :: () -> Gpu_Semaphore {
    return frame_timeline;
}

gpu_frame_index :: () -> u32 {
    return current_swapchain_index;
}

#scope_module

select_format :: (preferred_formats: [] Format) -> VkSurfaceFormatKHR {
    num_supported: u32;
    vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, *num_supported, null);

    supported_formats: [..] VkSurfaceFormatKHR;
    supported_formats.allocator = temp;
    array_resize(*supported_formats, num_supported);
    vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, *num_supported, supported_formats.data);

    for preferred_formats {
        vk_format := it.(VkFormat);
        for supported_formats {
            if it.format == vk_format return it;
        }
    }

    return .{VkFormat.B8G8R8A8_UNORM, .COLOR_SPACE_SRGB_NONLINEAR_KHR};
}

select_present_mode :: (preferred_modes: [] Present_Mode) -> VkPresentModeKHR {
    num_supported: u32;
    vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, *num_supported, null);

    supported_modes: [..] VkPresentModeKHR;
    supported_modes.allocator = temp;
    array_resize(*supported_modes, num_supported);
    vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, *num_supported, supported_modes.data);

    for preferred_modes {
        vk_mode := it.(VkPresentModeKHR);
        for supported_modes {
            if it == vk_mode return vk_mode;
        }
    }

    return .IMMEDIATE_KHR;
}

recreate_swapchain :: () {
    surface_capabilities: VkSurfaceCapabilitiesKHR;
    vk_result := vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, *surface_capabilities);
    assert_vk_result(vk_result);

    surface_extent = surface_capabilities.currentExtent;

    old_swapchain := vk_swapchain;

    cleanup_swapchain_image_views();

    // ref https://docs.vulkan.org/samples/latest/samples/performance/swapchain_images/README.html
    min_image_count: u32;
    if swapchain_present_mode == {
        case .FIFO_KHR; #through;
        case .IMMEDIATE_KHR;
            min_image_count = xx max(2, preferred_min_image_count);

        case .MAILBOX_KHR;
            min_image_count = xx max(3, preferred_min_image_count);
    }

    min_image_count = clamp(min_image_count, surface_capabilities.minImageCount, surface_capabilities.maxImageCount);

    create_info := VkSwapchainCreateInfoKHR.{
        surface = vk_surface,
        imageFormat = swapchain_format.format,
        imageColorSpace = swapchain_format.colorSpace,
        imageExtent = surface_extent,
        imageArrayLayers = 1,
        imageSharingMode = .EXCLUSIVE,
        imageUsage = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT | .STORAGE_BIT,
        minImageCount = min_image_count,
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
    debug_assert(min_image_count == image_count);

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
        assert_vk_result(vk_result);
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
    } else #if OS == .MACOS {
        assert(native_window_type == .COCOA);
        ns_window := cast(*NSWindow) native_window_handle;

        metal_layer := ns_window_get_metal_layer(ns_window);
        assert(metal_layer != null);

        create_info := VkMetalSurfaceCreateInfoEXT.{
            sType  = .METAL_SURFACE_CREATE_INFO_EXT,
            pNext  = null,
            flags  = 0,
            pLayer = metal_layer, // CAMetalLayer*
        };

        vk_result := vkCreateMetalSurfaceEXT(vk_instance, *create_info, null, *vk_surface);
        assert_vk_result(vk_result);
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
    array_reset(*swapchain_textures);
}


wait_next_frame :: () {
    gpu_wait_semaphore(.{gpu_frame_timeline, cpu_frame_timeline});
}

current_present_semaphore :: () -> VkSemaphore {
    return present_semaphores[current_swapchain_index];
}
current_acquire_semaphore :: () -> VkSemaphore {
    return acquire_semaphores[acquire_semaphore_index];
}

transition_swapchain_to_general :: (cmd_buff: Gpu_Command_Buffer) {
    vk_cmd_buff := get_cmd_buff(cmd_buff);

    image_barrier := VkImageMemoryBarrier2.{
        image = swapchain_images[current_swapchain_index],
        srcStageMask = 0,
        srcAccessMask = 0,
        dstStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
        subresourceRange = .{
            baseMipLevel = 0,
            baseArrayLayer = 0,
            levelCount = 1,
            layerCount = 1,
            aspectMask = get_image_aspect_mask(swapchain_format.format.(Format)),
        },
        oldLayout = .UNDEFINED,
        newLayout = .GENERAL,
    };

    dep_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier,
    };

    vkCmdPipelineBarrier2(vk_cmd_buff, *dep_info);
}


native_window_handle: u64;
native_window_type: Native_Window_Type;
vk_surface: VkSurfaceKHR;
surface_extent: VkExtent2D;

swapchain_present_mode: VkPresentModeKHR;
swapchain_format: VkSurfaceFormatKHR;

vk_swapchain: VkSwapchainKHR;

// These are sized according to how many swapchain images can be buffered. The actual sizes are a result of preference
// (gpu_init_swapchain()'s min_image_count and preferred_present_modes parameters) and platform support.
acquire_semaphores: [..] VkSemaphore;
present_semaphores: [..] VkSemaphore;

// gpu_frame_timeline represents the current frame index on the gpu
// while cpu_frame_timeline represents the current frame index on the cpu.
// The difference between GPU timeline and CPU timeline values should be the number of active frames in flight.
gpu_frame_timeline: Gpu_Semaphore;
cpu_frame_timeline: u64;

// #todo: these should be made static with a hard cap.
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
} else #if OS == .MACOS {
    #import "Objective_C";
    #import "Objective_C/AppKit";

    ns_window_get_metal_layer :: (window: *NSWindow) -> *CAMetalLayer {

        is_kind_of_class :: (obj: id, class: Class) -> bool {
            sel := sel_registerName("isKindOfClass:");
            func: (id, Selector, Class) -> BOOL #c_call;
            func = xx objc_msgSend;
            return func(obj, sel, class) == YES;
        }

        ns_view := NSWindow.contentView(window);
        if !ns_view {
            return null;
        }

        layer := NSView.layer(ns_view);
        if !layer {
            return null;
        }

        if !is_kind_of_class(cast(id) layer, objc_getClass("CAMetalLayer")) {
            return null;
        }

        return cast(*CAMetalLayer) layer;
    }
}
