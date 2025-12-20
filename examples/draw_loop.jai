main :: () {
    gpu_init();

    main_queue := gpu_get_queue(.MAIN, 0);

    v_success, vertex_spv := compile_shader("../shaders/basic_vs.slang");
    assert(v_success);
    p_success, pixel_spv := compile_shader("../shaders/basic_ps.slang");
    assert(p_success);

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .R8G8B8A8_UNORM}
        ],
        blend_state = *blend_state,
    };

    graphics_pipeline := gpu_create_graphics_pipeline(vertex_spv, pixel_spv, raster_desc);

    texture_desc := Gpu_Texture_Desc.{
        format = .R8G8B8A8_UNORM,
        dimensions = .[1024, 1024, 1],
        usage = .COLOR_ATTACHMENT
    };
    texture := gpu_create_texture(texture_desc);
    view := gpu_texture_view(texture);

    Vertex2D :: struct {
        x: float;
        y: float;
    }
    vertex_buffer, vertex_gpu := gpu_malloc(4 * size_of(Vertex2D));
    vertex_buffer.(*[4] Vertex2D).* = .[
        .{0.5, 0.5},
        .{0.5, -0.5},
        .{-0.5, -0.5},
        .{-0.5, +0.5},
    ];
    vertex_colors, colors_gpu := gpu_malloc(4 * 3 * size_of(float));
    vertex_colors.(*[12] float).* = .[
        1., 0., 0.,
        0., 1., 0.,
        0., 0., 1.,
        1., 1., 1.,
    ];

    param_block, vertex_params_gpu := gpu_malloc(2 * size_of(Gpu_Ptr));
    param_block.(*Gpu_Ptr)[0] = vertex_gpu;
    param_block.(*Gpu_Ptr)[1] = colors_gpu;

    index_buffer, index_gpu := gpu_malloc(6 * size_of(u32));
    index_buffer.(*[6] u32).* = .[
        0, 3, 1,
        1, 3, 2,
    ];

    pixel_data, pixel_gpu := gpu_malloc(3 * size_of(float));
    pixel_data.(*[3] float).* = .[1., 0., 1.];

    semaphore := gpu_create_semaphore(0);

    FRAMES_IN_FLIGHT :: 2;
    next_frame: u64 = 1;
    while true {
        if (next_frame > FRAMES_IN_FLIGHT) {
            gpu_wait_semaphore(semaphore, next_frame - FRAMES_IN_FLIGHT);
        }

        cmd_buff := gpu_start_command_recording(main_queue);
        {
            render_desc := Gpu_Render_Pass_Desc.{
                color_targets = .[
                    .{
                        view = view,
                        load_op = .CLEAR,
                        store_op = .STORE,
                        clear_color = .[0, 0, 0, 1],
                    }
                ]
            };
            gpu_begin_render_pass(cmd_buff, render_desc);

            gpu_set_pipeline(cmd_buff, graphics_pipeline);
            gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, 6, 1);

            gpu_end_render_pass(cmd_buff);
        }

        next_frame += 1;
        gpu_submit(main_queue, cmd_buff, signal = semaphore, signal_value = next_frame);

        if next_frame >= 100 then break;
    }

    gpu_wait_idle();

    gpu_free(vertex_buffer);
    gpu_free(index_buffer);
    gpu_free_pipeline(graphics_pipeline);
    gpu_free(texture);

    gpu_shutdown();
}

#load "common.jai";
#import "Basic";