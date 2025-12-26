main :: () {
    gpu_init();
    defer gpu_shutdown();

    // Using Jai's standard window library
    // window creation can be replaced with glfw/sdl/native. Just pass the native handle into `gpu_init_swapchain`.
    window := create_window(1280, 720, "Sample window");
    
    // Initialize the swapchain with any native window handle
    window_type: Native_Window_Type = #ifx OS == .WINDOWS then .WIN32 else .X11;
    gpu_init_swapchain(window, window_type);
    defer gpu_destroy_swapchain();

    // Built in slang shader compiler
    v_success, vertex_spv := compile_shader("../shaders/textured_vs.slang");
    assert(v_success);
    p_success, pixel_spv := compile_shader("../shaders/textured_ps.slang");
    assert(p_success);

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };

    // Link the shaders into a pipeline object. Notably all pipeline objects in sgpu use an identical pipeline layout.
    graphics_pipeline := gpu_create_graphics_pipeline(vertex_spv, pixel_spv, raster_desc);
    defer gpu_free_pipeline(graphics_pipeline);


    texture, view := load_texture("../sample.png", .R8G8B8A8_SRGB);
    sampler := gpu_create_sampler(.{ });
    defer gpu_free(texture);
    defer gpu_free(sampler);

    // Create a single arena in gpu memory to allocate vertex and index data
    gpu_arena := gpu_make_arena(1024);
    defer gpu_free_arena(gpu_arena);

    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [4] Vector2);
    vertex_buffer.* =  Vector2.[.{0.5, 0.5}, .{0.5, -0.5}, .{-0.5, -0.5}, .{-0.5, +0.5} ];

    vertex_uvs, uvs_gpu := gpu_arena_alloc(*gpu_arena, [4] Vector2);
    vertex_uvs.* = Vector2.[ .{1.0, 1.0}, .{1, 0.}, .{0., 0.}, .{0., 1} ];

    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [6] u32);
    index_buffer.* = u32.[ 0, 3, 1, 1, 3, 2 ];

    // Allocate a small block of memory where the vertex shader parameters will be stored.
    vs_param_block, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [2] Gpu_Ptr);
    vs_param_block.* = Gpu_Ptr.[ vertex_gpu, uvs_gpu ];

    // Allocate a small block of memory where the pixel shader parameters will be stored.
    pixel_data, pixel_gpu := gpu_arena_alloc(*gpu_arena, [2] u32);
    pixel_data.* = u32.[ view.(u32), sampler.(u32) ];

    main_queue := gpu_get_queue(.MAIN, 0);

    quit := false;
    while !quit {
        update_window_events();
        for events_this_frame {
            if it.type == .QUIT then quit = true;
        }
        if get_window_resizes().count > 0 {
            gpu_swapchain_resize();
        }

        // Acquires the next available swapchain image. This will wait on the internal semaphores until a frame is ready
        swapchain_image := gpu_swapchain_acquire();
        if !swapchain_image {
            continue;
        }

        cmd_buff := gpu_start_command_recording(main_queue);
        // Execute a render pass
        {
            render_desc := Gpu_Render_Pass_Desc.{
                color_targets = .[
                    .{
                        view = swapchain_image,
                        load_op = .CLEAR,
                        store_op = .STORE,
                        clear_color._float = .[0, 0, 0, 1],
                    }
                ]
            };
            gpu_begin_render_pass(cmd_buff, render_desc);
            gpu_set_depth_stencil_state(cmd_buff, .{ depth_test = .NEVER });

            gpu_set_pipeline(cmd_buff, graphics_pipeline);

            gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, 6, 1);

            gpu_end_render_pass(cmd_buff);
        }

        // submit the command buffer for presentation.
        gpu_submit_and_present(main_queue, cmd_buff);
    }

    gpu_wait_idle();
}

load_texture :: (filename: string, format: Format) -> Gpu_Texture, Gpu_Texture_View {
    assert(format == .R8G8B8A8_SRGB);

    stbi_set_flip_vertically_on_load(1);

    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(filename), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0 && num_channels == 4);

    texture := gpu_create_texture(.{
        dimensions = .[xx width, xx height, 1],
        format = format,
        usage = .SAMPLED | .TRANSFER_DST,
    });

    staging_size := 4 * width * height;
    staging, staging_gpu := gpu_malloc(staging_size);
    defer gpu_free(staging);

    memcpy(staging, pixels, staging_size);

    // #todo: use a transfer queue. make this non-blocking as well.
    transfer_queue := gpu_get_queue(.MAIN, 0);
    cmd_buff := gpu_start_command_recording(transfer_queue);

    gpu_copy_to_texture(cmd_buff, texture, staging_gpu);

    gpu_submit(transfer_queue, cmd_buff);

    gpu_wait_idle();

    view := gpu_texture_view(texture);

    return texture, view;
}

#import,file "../../simp_gpu/module.jai"(VALIDATION = true, ENABLE_RENDER_CAPTURE = false);
#import "Basic";
#import "Window_Creation"(DEFAULT_MSAA = 1);
#import "Input";
#import "stb_image";
#import "Math";