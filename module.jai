#module_parameters(VALIDATION := false, ENABLE_RENDER_CAPTURE := false);

Gpu_Pipeline :: #type,distinct s64;

Gpu_Texture :: #type,distinct s64;

Gpu_Texture_View :: #type,distinct s64;

Gpu_Sampler :: #type,distinct s64;

Gpu_Depth_Stencil_State :: #type,distinct s64;

Gpu_Blend_State :: #type,distinct s64;

Gpu_Queue :: #type,distinct s64;

Gpu_Command_Buffer :: #type,distinct s64;

Gpu_Semaphore :: #type,distinct s64;

Cull :: enum {
    NONE    :: 0x0;
    CCW     :: 0x1;
    CW      :: 0x2;
    ALL     :: 0x3;
}

Depth_Flags :: enum_flags u8 {
    NONE    :: 0;
    READ    :: 1 << 0;
    WRITE   :: 1 << 1;
}

Op :: enum {
    NEVER            :: 0;
    LESS             :: 1;
    EQUAL            :: 2;
    LESS_OR_EQUAL    :: 3;
    GREATER          :: 4;
    NOT_EQUAL        :: 5;
    GREATER_OR_EQUAL :: 6;
    ALWAYS           :: 7;
}

Load_Op :: enum {
    LOAD        :: 0;
    CLEAR       :: 1;
    DONT_CARE   :: 2;
}

Store_Op :: enum {
    STORE       :: 0;
    DONT_CARE   :: 1;
}

Stencil_Op :: enum {
    KEEP;
    ZERO;
    REPLACE;
    INVERT;
    INCREMENT_AND_CLAMP;
    DECREMENT_AND_CLAMP;
    INCREMENT_AND_WRAP;
    DECREMENT_AND_WARP;
}

Blend :: enum {
    ADD;
    SUBTRACT;
    REV_SUBTRACT;
    MIN;
    MAX;
}

Factor :: enum {
    ZERO                     :: 0;
    ONE                      :: 1;
    SRC_COLOR                :: 2;
    ONE_MINUS_SRC_COLOR      :: 3;
    DST_COLOR                :: 4;
    ONE_MINUS_DST_COLOR      :: 5;
    SRC_ALPHA                :: 6;
    ONE_MINUS_SRC_ALPHA      :: 7;
    DST_ALPHA                :: 8;
    ONE_MINUS_DST_ALPHA      :: 9;
    CONSTANT_COLOR           :: 10;
    ONE_MINUS_CONSTANT_COLOR :: 11;
    CONSTANT_ALPHA           :: 12;
    ONE_MINUS_CONSTANT_ALPHA :: 13;
    SRC_ALPHA_SATURATE       :: 14;
}

Component_Flags :: enum_flags {
    R   :: 0x01;
    G   :: 0x02;
    B   :: 0x04;
    A   :: 0x08;
    ALL :: R | G | B | A;
}

Topology :: enum {
    // #todo: nyi
    //POINT_LIST      :: 0;
    //LINE_LIST       :: 1;
    //LINE_STRIP      :: 2;
    TRIANGLE_LIST   :: 3;
    TRIANGLE_STRIP  :: 4;
    TRIANGLE_FAN    :: 5;
}

Texture_Type :: enum {
    _1D         :: 0;
    _2D         :: 1;
    _3D         :: 2;
    CUBE        :: 3;
    _1D_ARRAY   :: 4;
    _2D_ARRAY   :: 5;
    CUBE_ARRAY  :: 6;
}

Format :: enum {
    UNDEFINED                                      :: 0;
    R4G4_UNORM_PACK8                               :: 1;
    R4G4B4A4_UNORM_PACK16                          :: 2;
    B4G4R4A4_UNORM_PACK16                          :: 3;
    R5G6B5_UNORM_PACK16                            :: 4;
    B5G6R5_UNORM_PACK16                            :: 5;
    R5G5B5A1_UNORM_PACK16                          :: 6;
    B5G5R5A1_UNORM_PACK16                          :: 7;
    A1R5G5B5_UNORM_PACK16                          :: 8;
    R8_UNORM                                       :: 9;
    R8_SNORM                                       :: 10;
    R8_USCALED                                     :: 11;
    R8_SSCALED                                     :: 12;
    R8_UINT                                        :: 13;
    R8_SINT                                        :: 14;
    R8_SRGB                                        :: 15;
    R8G8_UNORM                                     :: 16;
    R8G8_SNORM                                     :: 17;
    R8G8_USCALED                                   :: 18;
    R8G8_SSCALED                                   :: 19;
    R8G8_UINT                                      :: 20;
    R8G8_SINT                                      :: 21;
    R8G8_SRGB                                      :: 22;
    R8G8B8_UNORM                                   :: 23;
    R8G8B8_SNORM                                   :: 24;
    R8G8B8_USCALED                                 :: 25;
    R8G8B8_SSCALED                                 :: 26;
    R8G8B8_UINT                                    :: 27;
    R8G8B8_SINT                                    :: 28;
    R8G8B8_SRGB                                    :: 29;
    B8G8R8_UNORM                                   :: 30;
    B8G8R8_SNORM                                   :: 31;
    B8G8R8_USCALED                                 :: 32;
    B8G8R8_SSCALED                                 :: 33;
    B8G8R8_UINT                                    :: 34;
    B8G8R8_SINT                                    :: 35;
    B8G8R8_SRGB                                    :: 36;
    R8G8B8A8_UNORM                                 :: 37;
    R8G8B8A8_SNORM                                 :: 38;
    R8G8B8A8_USCALED                               :: 39;
    R8G8B8A8_SSCALED                               :: 40;
    R8G8B8A8_UINT                                  :: 41;
    R8G8B8A8_SINT                                  :: 42;
    R8G8B8A8_SRGB                                  :: 43;
    B8G8R8A8_UNORM                                 :: 44;
    B8G8R8A8_SNORM                                 :: 45;
    B8G8R8A8_USCALED                               :: 46;
    B8G8R8A8_SSCALED                               :: 47;
    B8G8R8A8_UINT                                  :: 48;
    B8G8R8A8_SINT                                  :: 49;
    B8G8R8A8_SRGB                                  :: 50;
    A8B8G8R8_UNORM_PACK32                          :: 51;
    A8B8G8R8_SNORM_PACK32                          :: 52;
    A8B8G8R8_USCALED_PACK32                        :: 53;
    A8B8G8R8_SSCALED_PACK32                        :: 54;
    A8B8G8R8_UINT_PACK32                           :: 55;
    A8B8G8R8_SINT_PACK32                           :: 56;
    A8B8G8R8_SRGB_PACK32                           :: 57;
    A2R10G10B10_UNORM_PACK32                       :: 58;
    A2R10G10B10_SNORM_PACK32                       :: 59;
    A2R10G10B10_USCALED_PACK32                     :: 60;
    A2R10G10B10_SSCALED_PACK32                     :: 61;
    A2R10G10B10_UINT_PACK32                        :: 62;
    A2R10G10B10_SINT_PACK32                        :: 63;
    A2B10G10R10_UNORM_PACK32                       :: 64;
    A2B10G10R10_SNORM_PACK32                       :: 65;
    A2B10G10R10_USCALED_PACK32                     :: 66;
    A2B10G10R10_SSCALED_PACK32                     :: 67;
    A2B10G10R10_UINT_PACK32                        :: 68;
    A2B10G10R10_SINT_PACK32                        :: 69;
    R16_UNORM                                      :: 70;
    R16_SNORM                                      :: 71;
    R16_USCALED                                    :: 72;
    R16_SSCALED                                    :: 73;
    R16_UINT                                       :: 74;
    R16_SINT                                       :: 75;
    R16_SFLOAT                                     :: 76;
    R16G16_UNORM                                   :: 77;
    R16G16_SNORM                                   :: 78;
    R16G16_USCALED                                 :: 79;
    R16G16_SSCALED                                 :: 80;
    R16G16_UINT                                    :: 81;
    R16G16_SINT                                    :: 82;
    R16G16_SFLOAT                                  :: 83;
    R16G16B16_UNORM                                :: 84;
    R16G16B16_SNORM                                :: 85;
    R16G16B16_USCALED                              :: 86;
    R16G16B16_SSCALED                              :: 87;
    R16G16B16_UINT                                 :: 88;
    R16G16B16_SINT                                 :: 89;
    R16G16B16_SFLOAT                               :: 90;
    R16G16B16A16_UNORM                             :: 91;
    R16G16B16A16_SNORM                             :: 92;
    R16G16B16A16_USCALED                           :: 93;
    R16G16B16A16_SSCALED                           :: 94;
    R16G16B16A16_UINT                              :: 95;
    R16G16B16A16_SINT                              :: 96;
    R16G16B16A16_SFLOAT                            :: 97;
    R32_UINT                                       :: 98;
    R32_SINT                                       :: 99;
    R32_SFLOAT                                     :: 100;
    R32G32_UINT                                    :: 101;
    R32G32_SINT                                    :: 102;
    R32G32_SFLOAT                                  :: 103;
    R32G32B32_UINT                                 :: 104;
    R32G32B32_SINT                                 :: 105;
    R32G32B32_SFLOAT                               :: 106;
    R32G32B32A32_UINT                              :: 107;
    R32G32B32A32_SINT                              :: 108;
    R32G32B32A32_SFLOAT                            :: 109;
    R64_UINT                                       :: 110;
    R64_SINT                                       :: 111;
    R64_SFLOAT                                     :: 112;
    R64G64_UINT                                    :: 113;
    R64G64_SINT                                    :: 114;
    R64G64_SFLOAT                                  :: 115;
    R64G64B64_UINT                                 :: 116;
    R64G64B64_SINT                                 :: 117;
    R64G64B64_SFLOAT                               :: 118;
    R64G64B64A64_UINT                              :: 119;
    R64G64B64A64_SINT                              :: 120;
    R64G64B64A64_SFLOAT                            :: 121;
    B10G11R11_UFLOAT_PACK32                        :: 122;
    E5B9G9R9_UFLOAT_PACK32                         :: 123;
    D16_UNORM                                      :: 124;
    X8_D24_UNORM_PACK32                            :: 125;
    D32_SFLOAT                                     :: 126;
    S8_UINT                                        :: 127;
    D16_UNORM_S8_UINT                              :: 128;
    D24_UNORM_S8_UINT                              :: 129;
    D32_SFLOAT_S8_UINT                             :: 130;
    BC1_RGB_UNORM_BLOCK                            :: 131;
    BC1_RGB_SRGB_BLOCK                             :: 132;
    BC1_RGBA_UNORM_BLOCK                           :: 133;
    BC1_RGBA_SRGB_BLOCK                            :: 134;
    BC2_UNORM_BLOCK                                :: 135;
    BC2_SRGB_BLOCK                                 :: 136;
    BC3_UNORM_BLOCK                                :: 137;
    BC3_SRGB_BLOCK                                 :: 138;
    BC4_UNORM_BLOCK                                :: 139;
    BC4_SNORM_BLOCK                                :: 140;
    BC5_UNORM_BLOCK                                :: 141;
    BC5_SNORM_BLOCK                                :: 142;
    BC6H_UFLOAT_BLOCK                              :: 143;
    BC6H_SFLOAT_BLOCK                              :: 144;
    BC7_UNORM_BLOCK                                :: 145;
    BC7_SRGB_BLOCK                                 :: 146;
}

Usage_Flags :: enum_flags {
    NONE                        :: 0x0;
    TRANSFER_SRC                :: 0x1;
    TRANSFER_DST                :: 0x2;
    SAMPLED                     :: 0x4;
    STORAGE                     :: 0x8;
    COLOR_ATTACHMENT            :: 0x10;
    DEPTH_STENCIL_ATTACHMENT    :: 0x20;
}

Stage :: enum {
    TOP_OF_PIPE             :: 0x00000001;
    DRAW_INDIRECT           :: 0x00000002;
    VERTEX_INPUT            :: 0x00000004;
    VERTEX_SHADER           :: 0x00000008;
    PIXEL_SHADER            :: 0x00000080;
    MESH_SHADER             :: 0x00100000;
    EARLY_FRAGMENT_TESTS    :: 0x00000100;
    LATE_FRAGMENT_TESTS     :: 0x00000200;
    COLOR_ATTACHMENT_OUTPUT :: 0x00000400;
    COMPUTE_SHADER          :: 0x00000800;
    TRANSFER                :: 0x00001000;
    BOTTOM_OF_PIPE          :: 0x00002000;
    HOST                    :: 0x00004000;
    ALL                     :: 0x00010000;
}

Gpu_Queue_Type :: enum u8 {
    MAIN        :: 0;
    COMPUTE     :: 1;
    TRANSFER    :: 2;
}

Stencil_Desc :: struct {
    test: Op = .ALWAYS;
    fail_op: Stencil_Op = .KEEP;
    pass_op: Stencil_Op = .KEEP;
    depth_fail_op: Stencil_Op = .KEEP;
    reference: u8 = 0;
}

Gpu_Blend_Desc :: struct {
    color_op: Blend = .ADD;
    src_color_factor: Factor = .ONE;
    dst_color_factor: Factor = .ZERO;

    alpha_op: Blend = .ADD;
    src_alpha_factor: Factor = .ONE;
    dst_alpha_factor: Factor = .ZERO;

    color_write_mask: Component_Flags = .ALL;
}

Gpu_Depth_Stencil_Desc :: struct {
    depth_mode: Depth_Flags;
    depth_test: Op = .ALWAYS;

    depth_bias: float = 0.;
    depth_bias_slope_factor: float = 0.;
    depth_bias_clamp: float = 0.;

    stencil_read_mask: u8 = 0xff;
    stencil_write_mask: u8 = 0xff;

    stencil_front: Stencil_Desc;
    stencil_back: Stencil_Desc;
}

Color_Target :: struct {
    format: Format = .UNDEFINED;
}

Gpu_Raster_Desc :: struct {
    topology: Topology = .TRIANGLE_LIST;
    cull: Cull = .NONE;
    alpha_to_coverage := false;
    support_dual_source_blending := false;
    sample_count: u8 = 1;

    depth_format: Format = .UNDEFINED;
    stencil_format: Format = .UNDEFINED;
    
    color_targets: [] Color_Target;

    // Optional blend state baked into the pipeline.
    // else dynamic state.
    // blend state is duplicated to all color targets.
    blend_state: *Gpu_Blend_Desc;
}

Gpu_Texture_Desc :: struct {
    type: Texture_Type = ._2D;
    dimensions: [3] u32;

    mip_count: u8 = 1;
    layer_count: u16 = 1;
    sample_count: u32 = 1;

    format: Format = .UNDEFINED;
    usage: Usage_Flags = .NONE;
}

Gpu_View_Desc :: struct {
    format: Format = .UNDEFINED;
    base_mip: u8 = 0;
    mip_count: u8 = 0xFF; 
    base_layer: u16 = 0;
    layer_count: u16 = 0xFFFF;
}

Gpu_Sampler_Desc :: struct {
    Filter :: enum {
        NEAREST :: 0;
        LINEAR  :: 1;
    }

    Address_Mode :: enum {
        REPEAT                   :: 0;
        MIRRORED_REPEAT          :: 1;
        CLAMP_TO_EDGE            :: 2;
        CLAMP_TO_BORDER          :: 3;
        MIRROR_CLAMP_TO_EDGE     :: 4;
    }

    Border_Color :: enum {
        FLOAT_TRANSPARENT_BLACK :: 0;
        INT_TRANSPARENT_BLACK   :: 1;
        FLOAT_OPAQUE_BLACK      :: 2;
        INT_OPAQUE_BLACK        :: 3;
        FLOAT_OPAQUE_WHITE      :: 4;
        INT_OPAQUE_WHITE        :: 5;
    }

    min_filter: Filter = .LINEAR;
    mag_filter: Filter = .LINEAR;
    mip_filter: Filter = .LINEAR;

    address_mode_u: Address_Mode = .CLAMP_TO_EDGE;
    address_mode_v: Address_Mode = .CLAMP_TO_EDGE;
    address_mode_w: Address_Mode = .CLAMP_TO_EDGE;

    mip_lod_bias: float = 0.5;
    mip_lod: float = 0.;

    enable_anisotropy: bool = false;
    max_anisotropy: float = 0.;

    compare_op: Op = .ALWAYS;

    min_lod: float = 0.;
    max_lod: float = 1000.;

    border_color: Border_Color;

    unnormalized_coordinates: bool;
}

Gpu_Render_Pass_Attachment_Desc :: struct {
    view: Gpu_Texture_View;
    load_op: Load_Op;
    store_op: Store_Op;
    union {
        clear_value: float;
        clear_color: [4] u32;
    };
}

Gpu_Render_Pass_Desc :: struct {
    depth_target: Gpu_Render_Pass_Attachment_Desc;
    stencil_target: Gpu_Render_Pass_Attachment_Desc;
    color_targets: [] Gpu_Render_Pass_Attachment_Desc;
}

// ----------------------------- Global ------------------------------------

gpu_init :: () {
    #if ENABLE_RENDER_CAPTURE {
        gpu_capture_init();
    }
    create_instance();
    create_device();
    create_descriptor_buffer();
    create_global_pipeline_layout();
}

gpu_shutdown :: () {
    vkDeviceWaitIdle(vk_device);

    gpu_collect_garbage();

    for arena : cmd_pools {
        for arena.all_pools {
            vkDestroyCommandPool(vk_device, it.vk_cmd_pool, null);
        }
    }

    for queues {
        vkDestroySemaphore(vk_device, it.timeline, null);
    }

    #if VALIDATION {
        vkDestroyDebugReportCallbackEXT: PFN_vkDestroyDebugReportCallbackEXT = xx vkGetInstanceProcAddr(vk_instance, "vkDestroyDebugReportCallbackEXT");
        if vkDestroyDebugReportCallbackEXT != null {
            vkDestroyDebugReportCallbackEXT(vk_instance, vk_debug_callback_handle, null);
        }
    }

    vkDestroyPipelineLayout(vk_device, vk_pipeline_layout, null);
    destroy_bindless_buffer();
    vkDestroyDescriptorSetLayout(vk_device, bindless_set_layout, null);
    vmaDestroyAllocator(vma);
    vkDestroyDevice(vk_device, null);
    vkDestroyInstance(vk_instance, null);
}

gpu_collect_garbage :: () {
    reclaim_completed_command_pools();
}

// #TODO: is this required as part of the public api?
gpu_wait_idle :: () {
    vkDeviceWaitIdle(vk_device);
}


// ----------------------------- Queues ------------------------------------

gpu_get_queue :: (queue_type: Gpu_Queue_Type, queue_index: u32) -> Gpu_Queue {
    for queues {
        if it.type == queue_type && it.index == queue_index then return (it_index + 1).(Gpu_Queue);
    }
    return 0;
}

// ----------------------------- Semaphores ------------------------------------

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
    assert_vk_result(vk_result);

    handle := pool_add(*live_semaphores, .{vk_semaphore});

    return handle.(Gpu_Semaphore);
}

gpu_wait_semaphore :: (semaphore_handle: Gpu_Semaphore, value: u64) {
    semaphore := pool_get(live_semaphores, semaphore_handle);

    wait_info := VkSemaphoreWaitInfo.{
        semaphoreCount = 1,
        pSemaphores = *semaphore.vk_semaphore,
        pValues = *value,
    };
    vk_result := vkWaitSemaphores(vk_device, *wait_info, U64_MAX);
    assert_vk_result(vk_result);
}

gpu_destroy_semaphore :: (semaphore_handle: Gpu_Semaphore) {
    removed, semaphore := pool_remove(*live_semaphores, semaphore_handle);
    assert(removed);
    vkDestroySemaphore(vk_device, semaphore.vk_semaphore, null);
}

#load "pool.jai";
#load "memory.jai";
#load "command_buffer.jai";
#load "textures.jai";
#load "bindless.jai";
#load "pipeline.jai";
#load "shader_compiler.jai";
#load "render_capture.jai";
#load "gpu_arena.jai";
#load "swapchain.jai";

#scope_module

assert_vk_result :: (result: VkResult) {
    assert(result == VkResult.SUCCESS);
}

create_instance :: () {
    auto_release_temp();
    push_allocator(temp);

    result: VkResult;

    optional_extensions: [..] string;
    array_add(*optional_extensions, VK_KHR_SURFACE_EXTENSION_NAME);
    array_add(*optional_extensions, "VK_KHR_win32_surface");
    array_add(*optional_extensions, "VK_KHR_wayland_surface");
    array_add(*optional_extensions, "VK_KHR_xlib_surface");

    // find extensions
    enabled_extensions: [..] *u8;
    #if VALIDATION {
        array_add(*enabled_extensions, VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
        array_add(*enabled_extensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }
    {
        count: u32;
        result = vkEnumerateInstanceExtensionProperties(null, *count, null);
        assert_vk_result(result);

        available_extensions: [..] VkExtensionProperties;
        array_resize(*available_extensions, count);

        result = vkEnumerateInstanceExtensionProperties(null, *count, available_extensions.data);
        assert_vk_result(result);

        for optional : optional_extensions {
            for available : available_extensions {
                if optional == to_string(available.extensionName) {
                    array_add(*enabled_extensions, optional.data);
                    break available;
                }
            }
        }
    }

    app_info: VkApplicationInfo;
    app_info.apiVersion = VK_API_VERSION_1_3;
    app_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);

    create_info: VkInstanceCreateInfo;
    create_info.pApplicationInfo = *app_info;
    create_info.enabledExtensionCount = enabled_extensions.count.(u32);
    create_info.ppEnabledExtensionNames = enabled_extensions.data;
    #if VALIDATION {
        create_info.enabledLayerCount = 1;
        create_info.ppEnabledLayerNames = (*u8).["VK_LAYER_KHRONOS_validation"].data;

        enabled_validation_features := VkValidationFeatureEnableEXT.[
            //.GPU_ASSISTED_EXT,
            //.GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT,
            .SYNCHRONIZATION_VALIDATION_EXT,
        ];

        validation_features := VkValidationFeaturesEXT.{
            enabledValidationFeatureCount = enabled_validation_features.count,
            pEnabledValidationFeatures  = enabled_validation_features.data,
        };

        debug_messenger_create_info := VkDebugUtilsMessengerCreateInfoEXT.{
            messageSeverity = .WARNING_BIT_EXT | .ERROR_BIT_EXT,
            messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT | .PERFORMANCE_BIT_EXT,
            pfnUserCallback = vk_debug_callback,
            pUserData = null,
            pNext = *validation_features,
        };

        create_info.pNext = *debug_messenger_create_info;
    }

    result = vkCreateInstance(*create_info, null, *vk_instance);
    assert_vk_result(result);

    #if VALIDATION {
        vkCreateDebugReportCallbackEXT: PFN_vkCreateDebugReportCallbackEXT = xx vkGetInstanceProcAddr(vk_instance, "vkCreateDebugReportCallbackEXT");

        if vkCreateDebugReportCallbackEXT {
            debug_callback_create_info: VkDebugReportCallbackCreateInfoEXT;
            debug_callback_create_info.flags |= .ERROR_BIT_EXT;
            debug_callback_create_info.flags |= .WARNING_BIT_EXT;
            debug_callback_create_info.pfnCallback = vk_validation_callback;

            vkCreateDebugReportCallbackEXT(vk_instance, *debug_callback_create_info, null, *vk_debug_callback_handle);
        }
    }
}

create_device :: () {
    auto_release_temp();
    push_allocator(temp);

    required_extensions: [..] *u8;
    array_add(*required_extensions, VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME);
    array_add(*required_extensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    array_add(*required_extensions, "VK_KHR_synchronization2");
    array_add(*required_extensions, "VK_EXT_descriptor_buffer");
    // #todo: praise the unified layouts! (still not widely available).
    //array_add(*required_extensions, "VK_KHR_unified_layouts");

    result: VkResult;

    // pick the best physical device
    {
        device_handles: [..] VkPhysicalDevice;
        device_scores: [..] s32;

        physical_device_count: u32;
        result = vkEnumeratePhysicalDevices(vk_instance, *physical_device_count, null);
        assert_vk_result(result);

        array_resize(*device_handles, physical_device_count);
        array_resize(*device_scores, physical_device_count);
        result = vkEnumeratePhysicalDevices(vk_instance, *physical_device_count, device_handles.data);
        assert_vk_result(result);

        assert(physical_device_count > 0);


        for device_handles {
            device_properties: VkPhysicalDeviceProperties2;
            device_features: VkPhysicalDeviceFeatures2;
            vkGetPhysicalDeviceProperties2(it, *device_properties);
            vkGetPhysicalDeviceFeatures2(it, *device_features);

            limits_satisfied := device_properties.properties.limits.maxDescriptorSetStorageBuffers >= MAX_BUFFERS
                && device_properties.properties.limits.maxDescriptorSetStorageImages >= MAX_IMAGES
                && device_properties.properties.limits.maxDescriptorSetSampledImages >= MAX_IMAGES;
            
            if !limits_satisfied then continue;

            if device_properties.properties.deviceType == .DISCRETE_GPU {
                device_scores[it_index] += 1000;
            } else if device_properties.properties.deviceType == .VIRTUAL_GPU {
                device_scores[it_index] += 100;
            } else if device_properties.properties.deviceType == .INTEGRATED_GPU {
                device_scores[it_index] += 10;
            }
        }

        best_device_index: s64 = 0;
        best_score: s32 = 0;
        for device_scores {
            if it > best_score {
                best_score = it;
                best_device_index = it_index;
            }
        }

        assert(best_score > 0, "None of the available physical devices satisfy the minimum requirements!");
        vk_physical_device = device_handles[best_device_index];
        vkGetPhysicalDeviceProperties2(vk_physical_device, *vk_physical_device_properties);
    }

    // Set up the requests for queue creation
    queue_create_infos: [3] VkDeviceQueueCreateInfo;
    {
        queue_priorities := float.[0., 0., 0., 0.];
        queue_family_properties: [..] VkQueueFamilyProperties;
        supports_present: [..] bool;

        queue_family_count: u32;
        vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, *queue_family_count, null);
        array_resize(*queue_family_properties, queue_family_count);
        array_resize(*supports_present, queue_family_count);
        vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, *queue_family_count, queue_family_properties.data);

        Queue_Create_Info :: struct {
            family: u32 = U32_MAX;
            count: u32;
        }

        infos: [3] Queue_Create_Info;
        for queue_family_properties {
            supports_graphics := it.queueFlags & .GRAPHICS_BIT;
            supports_compute  := it.queueFlags & .COMPUTE_BIT;
            supports_transfer := it.queueFlags & .TRANSFER_BIT;

            // primary queue should support all operations
            if infos[0].family == U32_MAX && supports_graphics && supports_compute && supports_transfer {
                infos[0].family = it_index.(u32);
                infos[0].count = 1;
            }
            // compute queues should support compute/transfer
            if infos[1].family == U32_MAX && !supports_graphics && supports_compute && supports_transfer {
                infos[1] = .{
                    family = it_index.(u32),
                    count = min(it.queueCount, MAX_COMPUTE_QUEUES),
                };
            }
            if infos[2].family == U32_MAX && !supports_graphics && !supports_compute && supports_transfer {
                infos[2] = .{
                    family = it_index.(u32),
                    count = min(it.queueCount, MAX_TRANSFER_QUEUES),
                };
            }
        }

        for infos {
            queue_create_infos[it_index] = .{
                queueFamilyIndex = it.family,
                queueCount = it.count,
                pQueuePriorities = queue_priorities.data
            };
        }
    }

    // create the device:
    {
        chain: *void;
        dynamic_rendering := VkPhysicalDeviceDynamicRenderingFeatures.{ pNext = chain, dynamicRendering = VK_TRUE };
        chain = *dynamic_rendering;

        descriptor_buffer := VkPhysicalDeviceDescriptorBufferFeaturesEXT.{
            pNext = chain,
            descriptorBuffer = VK_TRUE,
            descriptorBufferImageLayoutIgnored = VK_TRUE,
        };
        chain = *descriptor_buffer;

        synchronization2 := VkPhysicalDeviceSynchronization2Features.{
            pNext = chain,
            synchronization2 = VK_TRUE,
        };
        chain = *synchronization2;

        vk12_features := VkPhysicalDeviceVulkan12Features.{
            pNext = chain,
            bufferDeviceAddress = VK_TRUE,
            descriptorBindingPartiallyBound = VK_TRUE,
            descriptorBindingSampledImageUpdateAfterBind = VK_TRUE,
            descriptorBindingStorageBufferUpdateAfterBind = VK_TRUE,
            descriptorBindingStorageImageUpdateAfterBind = VK_TRUE,
            descriptorBindingStorageTexelBufferUpdateAfterBind = VK_TRUE,
            descriptorBindingUniformBufferUpdateAfterBind = VK_TRUE,
            descriptorBindingUniformTexelBufferUpdateAfterBind = VK_TRUE,
            descriptorBindingUpdateUnusedWhilePending = VK_TRUE,
            descriptorBindingVariableDescriptorCount = VK_TRUE,
            descriptorIndexing = VK_TRUE,
            runtimeDescriptorArray = VK_TRUE,
            scalarBlockLayout = VK_TRUE,
            shaderBufferInt64Atomics = VK_TRUE,
            shaderFloat16 = VK_TRUE,
            shaderInputAttachmentArrayDynamicIndexing = VK_TRUE,
            shaderInputAttachmentArrayNonUniformIndexing = VK_TRUE,
            shaderInt8 = VK_TRUE,
            shaderSampledImageArrayNonUniformIndexing = VK_TRUE,
            shaderStorageBufferArrayNonUniformIndexing = VK_TRUE,
            shaderStorageImageArrayNonUniformIndexing = VK_TRUE,
            shaderStorageTexelBufferArrayDynamicIndexing = VK_TRUE,
            shaderStorageTexelBufferArrayNonUniformIndexing = VK_TRUE,
            shaderUniformBufferArrayNonUniformIndexing = VK_TRUE,
            shaderUniformTexelBufferArrayDynamicIndexing = VK_TRUE,
            shaderUniformTexelBufferArrayNonUniformIndexing = VK_TRUE,
            storageBuffer8BitAccess = VK_TRUE,
            storagePushConstant8 = VK_TRUE,
            timelineSemaphore = VK_TRUE,
            uniformAndStorageBuffer8BitAccess = VK_TRUE,
            vulkanMemoryModel = VK_TRUE,
            vulkanMemoryModelDeviceScope = VK_TRUE,
        };
        chain = *vk12_features;

        vk11_features := VkPhysicalDeviceVulkan11Features.{
            pNext = chain,
            variablePointersStorageBuffer = VK_TRUE,
            variablePointers = VK_TRUE,
            storagePushConstant16 = VK_TRUE,
            shaderDrawParameters = VK_TRUE,
        };
        chain = *vk11_features;

        device_features := VkPhysicalDeviceFeatures.{
        };

        create_info := VkDeviceCreateInfo.{
            pNext = chain,
            queueCreateInfoCount = queue_create_infos.count.(u32),
            pQueueCreateInfos = queue_create_infos.data,

            enabledExtensionCount = required_extensions.count.(u32),
            ppEnabledExtensionNames = required_extensions.data,

            pEnabledFeatures = *device_features,
        };

        result = vkCreateDevice(vk_physical_device, *create_info, null, *vk_device);
        assert_vk_result(result);
    }

    // initialize the queues:
    {
        queue_index: u32 = 0;
        for queue_create_infos {
            for queue_index_in_family : 0..it.queueCount-1 {
                vkGetDeviceQueue(vk_device, it.queueFamilyIndex, queue_index_in_family, *queues[queue_index].vk_queue);
                assert(queues[queue_index].vk_queue != VK_NULL_HANDLE);

                queues[queue_index].vk_family = it.queueFamilyIndex;

                queue_index += 1;
            }
            all_queue_family_indices[it_index] = it.queueFamilyIndex;
        }

        // create the timeline semaphores for each queue:
        for * queues {
            timeline_create_info := VkSemaphoreTypeCreateInfo.{
                semaphoreType = .TIMELINE,
                initialValue = 0
            };
            create_info := VkSemaphoreCreateInfo.{
                pNext = *timeline_create_info,
            };

            result = vkCreateSemaphore(vk_device, *create_info, null, *it.timeline);
            assert_vk_result(result);
        }
    }

    // initialize VMA for memory allocations
    {
        memory_properties: VkPhysicalDeviceMemoryProperties;
        vkGetPhysicalDeviceMemoryProperties(vk_physical_device, *memory_properties);

        allocator_info := VmaAllocatorCreateInfo.{
            physicalDevice = vk_physical_device,
            device = vk_device,
            instance = vk_instance,
            vulkanApiVersion = VK_API_VERSION_1_3,
            flags = .BUFFER_DEVICE_ADDRESS_BIT,
        };

        result = vmaCreateAllocator(*allocator_info, *vma);
        assert_vk_result(result);
    }

    // load extension function pointers
    {
        #insert #run generate_get_device_proc_addr("vkCmdBeginRenderingKHR");
        #insert #run generate_get_device_proc_addr("vkCmdEndRenderingKHR");
        #insert #run generate_get_device_proc_addr("vkGetDescriptorSetLayoutSizeEXT");
        #insert #run generate_get_device_proc_addr("vkGetDescriptorSetLayoutBindingOffsetEXT");
        #insert #run generate_get_device_proc_addr("vkGetDescriptorSetLayoutBindingOffsetEXT");
        #insert #run generate_get_device_proc_addr("vkGetDescriptorEXT");
        #insert #run generate_get_device_proc_addr("vkCmdBindDescriptorBuffersEXT");
        #insert #run generate_get_device_proc_addr("vkCmdSetDescriptorBufferOffsetsEXT");
    }
}

generate_get_device_proc_addr :: (proc_name: string) ->string #compile_time {
    INSERT_STRING :: #string DONE
        %1 = cast(PFN_%1) vkGetDeviceProcAddr(vk_device, "%1");
        assert(%1 != null);
    DONE;

    return tprint(INSERT_STRING, proc_name);
}

vk_instance: VkInstance;
vk_physical_device: VkPhysicalDevice;
vk_physical_device_properties: VkPhysicalDeviceProperties2;
vk_device: VkDevice;
vma: VmaAllocator;

Queue :: struct {
    vk_queue: VkQueue;
    vk_family: u32;
    index: u32;
    type: Gpu_Queue_Type;
    
    timeline: VkSemaphore;
    timeline_value: u64;
}

queues := Queue.[
    .{type = .MAIN, index = 0},
    .{type = .COMPUTE, index = 0},
    .{type = .COMPUTE, index = 1},
    .{type = .COMPUTE, index = 2},
    .{type = .COMPUTE, index = 3},
    .{type = .TRANSFER, index = 0},
    .{type = .TRANSFER, index = 1},
];

/** The number of queue families should always at most one per queue type. */
NUM_QUEUE_FAMILIES :: #run enum_highest_value(Gpu_Queue_Type) + 1;

all_queue_family_indices: [NUM_QUEUE_FAMILIES] u32;

get_queue :: (queue_handle: Gpu_Queue) -> *Queue {
    queue_index := queue_handle - 1;
    assert(queue_index < queues.count);
    return *queues[queue_index];
}

Semaphore :: struct {
    vk_semaphore: VkSemaphore;
}

get_semaphore :: (semaphore_handle: Gpu_Semaphore) -> VkSemaphore {
    semaphore := pool_get(live_semaphores, semaphore_handle);
    assert(semaphore != null);
    return semaphore.vk_semaphore;
}

live_semaphores: Pool(Gpu_Semaphore, Semaphore);

MAX_BUFFERS  :: 10000;
MAX_IMAGES   :: 10000;
MAX_SAMPLERS :: 1000;

MAX_COMPUTE_QUEUES  :: 4;
MAX_TRANSFER_QUEUES :: 2;

// 16 seems like a reasonable cap on this. Prevents some unnecessary heap allocations
MAX_ATTACHMENTS :: 16;

vkCmdBeginRenderingKHR : PFN_vkCmdBeginRenderingKHR;
vkCmdEndRenderingKHR : PFN_vkCmdEndRenderingKHR;

#if VALIDATION {
    vk_debug_callback_handle: VkDebugReportCallbackEXT;

    vk_validation_callback :: (flags: VkDebugReportFlagsEXT, objType: VkDebugReportObjectTypeEXT, obj: u64, location: u64, code: s32, layerPrefix: *u8, msg: *u8, userData: *void) -> VkBool32 #c_call {
        new_context: #Context;
        push_context new_context {
            msg_string := to_string(msg);
            // ignore messages about missing usage flag INDEX_BUFFER_BIT.
            if contains(msg_string, "requires VK_BUFFER_USAGE_2_INDEX_BUFFER_BIT") then return VK_FALSE;

            log("Vulkan Validation: %", to_string(msg));
        }
        
        return VK_FALSE;
    }

    vk_debug_callback :: (messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: *VkDebugUtilsMessengerCallbackDataEXT, pUserData: *void) -> VkBool32 #c_call {
        new_context: #Context;
        push_context new_context {
            if messageSeverity == {
                case .WARNING_BIT_EXT;
                    log("Vulkan debug: %", to_string(pCallbackData.pMessage));
                case .ERROR_BIT_EXT;
                    log("Vulkan debug: %", to_string(pCallbackData.pMessage));
            }
        }

        return VK_FALSE;
    }
}

#import,file "modules/Vulkan_With_VMA/module.jai";

#import "Basic";
#import "String";
#import "Math";
#import "Bucket_Array";
#import "Atomics";
