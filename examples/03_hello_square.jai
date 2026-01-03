main :: () {
    result := gpu_init();
    assert(result == .SUCCESS);
    defer gpu_shutdown();

    #if OS == .MACOS {
        window := create_window_metal(1280, 720, "Sample window");
    } else {
        window := create_window(1280, 720, "Sample window");
    }

    window_type: Native_Window_Type;

    #if      OS == .WINDOWS then  window_type = .WIN32;
    else #if OS == .LINUX   then window_type = .X11;
    else #if OS == .MACOS   then window_type = .COCOA;
    else assert(false, "Unsupported OS");

    gpu_init_swapchain(window.(u64), window_type);
    defer gpu_destroy_swapchain();

    main_queue := gpu_get_queue(.MAIN, 0);

    success, vertex_spv := compile_shader("../shaders/hello_square_vs.slang");
    assert(success);
    success=, pixel_spv := compile_shader("../shaders/hello_square_ps.slang");
    assert(success);

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
    defer gpu_free_pipeline(graphics_pipeline);

    Vertex2D :: struct {
        x: float;
        y: float;
    }

    gpu_arena := gpu_make_arena(1024);
    defer gpu_free_arena(gpu_arena);

    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [4] Vertex2D);
    vertex_buffer.* = .[
        .{ 0.5,   0.5 },
        .{ 0.5,  -0.5 },
        .{ -0.5, -0.5 },
        .{ -0.5, +0.5 },
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

    quit := false;
    while !quit {
        update_window_events();
        for events_this_frame {
            if it.type == .QUIT then quit = true;
        }
        if get_window_resizes().count > 0 {
            gpu_swapchain_resize();
        }

        result=, swapchain_image := gpu_swapchain_acquire();
        assert(result == .SUCCESS);
        if !swapchain_image {
            continue;
        }

        result=, cmd_buff := gpu_start_command_recording(main_queue);
        assert(result == .SUCCESS);
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
            gpu_set_depth_stencil_state(cmd_buff, depth_desc);

            gpu_set_pipeline(cmd_buff, graphics_pipeline);

            gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, 6, 1);

            gpu_end_render_pass(cmd_buff);
        }

        gpu_submit_and_present(cmd_buff);
    }

    gpu_wait_idle();
}

#import,file "../module.jai"(VALIDATION = true);
#import "Basic";
#import "Window_Creation"(DEFAULT_MSAA = 1);
#import "Input";

#if OS == .MACOS {
    #import "Objective_C";
    #import "Objective_C/AppKit";
    #import "Metal";
    #load "macos_window.jai";
}
