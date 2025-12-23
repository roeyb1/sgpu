main :: () {
    gpu_init();

    window := create_window(1280, 720, "Sample window");
    gpu_init_swapchain(window, .X11);

    main_queue := gpu_get_queue(.MAIN, 0);

    v_success, vertex_spv := compile_shader("../shaders/basic_vs.slang");
    assert(v_success);
    p_success, pixel_spv := compile_shader("../shaders/basic_ps.slang");
    assert(p_success);

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };
    depth_desc := Gpu_Depth_Stencil_Desc.{
        depth_test = .NEVER,
        depth_mode = .NONE,
    };

    graphics_pipeline := gpu_create_graphics_pipeline(vertex_spv, pixel_spv, raster_desc);

    Vertex2D :: struct {
        x: float;
        y: float;
    }

    gpu_arena := gpu_make_arena(1024);

    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [4] Vertex2D);
    vertex_buffer.* = .[
        .{0.5, 0.5},
        .{0.5, -0.5},
        .{-0.5, -0.5},
        .{-0.5, +0.5},
    ];

    vertex_colors, colors_gpu := gpu_arena_alloc(*gpu_arena, [12] float);
    vertex_colors.* = .[
        1., 0., 0.,
        0., 1., 0.,
        0., 0., 1.,
        1., 1., 1.,
    ];

    param_block, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [2] Gpu_Ptr);
    param_block.* = .[vertex_gpu, colors_gpu];

    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [6] u32);
    index_buffer.* = .[
        0, 3, 1,
        1, 3, 2,
    ];

    pixel_data, pixel_gpu := gpu_arena_alloc(*gpu_arena, [3] float);
    pixel_data.* = .[1., 0., 1.];

    FRAMES_IN_FLIGHT :: 2;
    quit := false;
    frame_index := 0;
    while !quit {
        defer frame_index += 1;
        update_window_events();
        for events_this_frame {
            if it.type == .QUIT then quit = true;
        }
        if get_window_resizes().count > 0 {
            gpu_swapchain_resize();
        }

        swapchain_image := gpu_swapchain_acquire();
        if !swapchain_image {
            continue;
        }

        cmd_buff := gpu_start_command_recording(main_queue);
        {
            render_desc := Gpu_Render_Pass_Desc.{
                color_targets = .[
                    .{
                        view = swapchain_image,
                        load_op = .CLEAR,
                        store_op = .STORE,
                        clear_color = .[0, 0, 0, 1],
                    }
                ]
            };
            gpu_begin_render_pass(cmd_buff, render_desc);
            gpu_set_depth_stencil_state(cmd_buff, depth_desc);

            gpu_set_pipeline(cmd_buff, graphics_pipeline);

            gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, 6, 1);

            gpu_end_render_pass(cmd_buff);
        }

        gpu_submit_and_present(main_queue, cmd_buff);
    }

    gpu_wait_idle();

    gpu_free_arena(gpu_arena);
    gpu_free_pipeline(graphics_pipeline);

    gpu_destroy_swapchain();

    gpu_shutdown();
}

#import,file "../../simp_gpu/module.jai"(VALIDATION = true);
#import "Basic";
#import "Window_Creation"(DEFAULT_MSAA = 1);
#import "Input";