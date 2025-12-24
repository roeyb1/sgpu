#scope_export

gpu_create_compute_pipeline :: (spirv: [] u8) -> Gpu_Pipeline {
    stage := create_shader_stage(spirv, .COMPUTE_BIT);

    create_info := VkComputePipelineCreateInfo.{
        stage = stage,
        layout = vk_pipeline_layout,
    };

    vk_pipeline: VkPipeline;
    vk_result := vkCreateComputePipelines(vk_device, null, 1, *create_info, null, *vk_pipeline);
    assert_vk_result(vk_result);

    vkDestroyShaderModule(vk_device, stage.module, null);

    handle := pool_add(*live_pipelines, .{.COMPUTE, vk_pipeline});
    return handle;
}

gpu_create_graphics_pipeline :: (vertex_spirv: [] u8, pixel_spirv: [] u8, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    shader_stages := VkPipelineShaderStageCreateInfo.[
        create_shader_stage(vertex_spirv, .VERTEX_BIT),
        create_shader_stage(pixel_spirv, .FRAGMENT_BIT)
    ];

    attachment_formats: [MAX_ATTACHMENTS] VkFormat;

    assert(raster_desc.color_targets.count < attachment_formats.count);
    for raster_desc.color_targets {
        attachment_formats[it_index] = it.format.(VkFormat);
    }

    pipeline_rendering_create_info := VkPipelineRenderingCreateInfo.{
        viewMask = 0,
        colorAttachmentCount = raster_desc.color_targets.count.(u32),
        pColorAttachmentFormats = attachment_formats.data,
        depthAttachmentFormat = raster_desc.depth_format.(VkFormat),
        stencilAttachmentFormat = raster_desc.stencil_format.(VkFormat),
    };

    // no vertex input. Everything is dynamically fetched.
    vertex_input_state := VkPipelineVertexInputStateCreateInfo.{};

    input_assembly_state := VkPipelineInputAssemblyStateCreateInfo.{
        topology = raster_desc.topology.(VkPrimitiveTopology),
        primitiveRestartEnable = VK_FALSE,
    };

    viewport := VkViewport.{x = 0, y = 0, width = 1., height = 0, minDepth = 0., maxDepth = 1.};
    scissor := VkRect2D.{offset = .{0, 0}, extent = .{0, 0}};
    viewport_state := VkPipelineViewportStateCreateInfo.{
        viewportCount = 1,
        pViewports = *viewport,
        scissorCount = 1,
        pScissors = *scissor,
    };

    rasterization_state := VkPipelineRasterizationStateCreateInfo.{
        depthClampEnable = VK_FALSE,
        rasterizerDiscardEnable = VK_FALSE,
        polygonMode = .FILL,
        cullMode = raster_desc.cull.(VkCullModeFlags),
        frontFace = .COUNTER_CLOCKWISE,
        lineWidth = 1.,
    };

    multisample_state := VkPipelineMultisampleStateCreateInfo.{
        rasterizationSamples = raster_desc.sample_count.(VkSampleCountFlagBits),
        alphaToCoverageEnable = raster_desc.alpha_to_coverage.(VkBool32),
    };

    assert(raster_desc.blend_state != null, "dynamic blend state is not yet implemented");
    attachment_blend_states: [MAX_ATTACHMENTS] VkPipelineColorBlendAttachmentState;
    for 0..raster_desc.color_targets.count-1 {
        attachment_blend_states[it] = .{
            blendEnable = VK_TRUE,
            srcColorBlendFactor = raster_desc.blend_state.src_color_factor.(VkBlendFactor),
            dstColorBlendFactor = raster_desc.blend_state.dst_color_factor.(VkBlendFactor),
            colorBlendOp = raster_desc.blend_state.color_op.(VkBlendOp),
            srcAlphaBlendFactor = raster_desc.blend_state.src_alpha_factor.(VkBlendFactor),
            dstAlphaBlendFactor = raster_desc.blend_state.dst_alpha_factor.(VkBlendFactor),
            alphaBlendOp = raster_desc.blend_state.alpha_op.(VkBlendOp),
            colorWriteMask = raster_desc.blend_state.color_write_mask.(VkColorComponentFlagBits),
        };
    }

    color_blend_state := VkPipelineColorBlendStateCreateInfo.{
        logicOpEnable = VK_FALSE,
        //logicOp
        attachmentCount = raster_desc.color_targets.count.(u32),
        pAttachments = attachment_blend_states.data,
    };

    dynamic_states := VkDynamicState.[
        .VIEWPORT, .SCISSOR, .DEPTH_BIAS, .DEPTH_TEST_ENABLE, .DEPTH_WRITE_ENABLE, .DEPTH_COMPARE_OP,
        // Fill some more space which can be filled by optional dynamic state:
        .MAX_ENUM, .MAX_ENUM, .MAX_ENUM, .MAX_ENUM, .MAX_ENUM, .MAX_ENUM,
    ];
    found, num_dynamic_states := array_find(dynamic_states, .MAX_ENUM);

    dynamic_state := VkPipelineDynamicStateCreateInfo.{
        dynamicStateCount = num_dynamic_states.(u32),
        pDynamicStates = dynamic_states.data
    };

    // #todo:
    //if !raster_desc.blend_state {
    //    dynamic_states[num_dynamic_states] = .COLOR_BLEND_ENABLE;
    //    num_dynamic_states += 1;
    //}

    pipeline_create_info := VkGraphicsPipelineCreateInfo.{
        flags = .CREATE_DESCRIPTOR_BUFFER_BIT_EXT,
        pNext = *pipeline_rendering_create_info,
        stageCount = shader_stages.count.(u32),
        pStages = shader_stages.data,
        pVertexInputState = *vertex_input_state,
        pInputAssemblyState = *input_assembly_state,
        pViewportState = *viewport_state,
        pRasterizationState = *rasterization_state,
        pMultisampleState = *multisample_state,
        pColorBlendState = *color_blend_state,
        pDynamicState = *dynamic_state,
        layout = vk_pipeline_layout,
        subpass = 0,
        basePipelineHandle = VK_NULL_HANDLE,
        basePipelineIndex = 0,
    };

    vk_pipeline: VkPipeline;
    vk_result := vkCreateGraphicsPipelines(vk_device, null, 1, *pipeline_create_info, null, *vk_pipeline);

    for shader_stages {
        vkDestroyShaderModule(vk_device, it.module, null);
    }
    
    handle := pool_add(*live_pipelines, .{.GRAPHICS, vk_pipeline});
    return handle;
}

gpu_free_pipeline :: (pipeline: Gpu_Pipeline) {
    removed, pipeline := pool_remove(*live_pipelines, pipeline);
    assert(removed);

    vkDestroyPipeline(vk_device, pipeline.vk_pipeline, null);
}

#scope_module

Pipeline_Type :: enum {
    GRAPHICS;
    COMPUTE;
}

Shader_Stage :: enum {
    VERTEX  :: 0x1;
    PIXEL   :: 0x10;
    COMPUTE :: 0x20;
    //MESH    :: 0x80;
}

NUM_SHADER_STAGES :: #run enum_values_as_enum(Shader_Stage).count;

Pipeline :: struct {
    type: Pipeline_Type;

    vk_pipeline: VkPipeline;
}

// we always use the same push constant block size and same descriptor sets so there is no need to have multiple pipeline layouts.
vk_pipeline_layout: VkPipelineLayout;
live_pipelines: Pool(Gpu_Pipeline, Pipeline);

create_global_pipeline_layout :: () {
    push_const_ranges: [NUM_SHADER_STAGES] VkPushConstantRange;
    ALL_STAGES :: #run enum_values_as_enum(Shader_Stage);
    for ALL_STAGES {
        push_const_ranges[it_index] = .{
            offset = it_index.(u32) * size_of(VkDeviceAddress),
            size = size_of(VkDeviceAddress),
            stageFlags = it.(VkShaderStageFlags),
        };
    }

    create_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *bindless_set_layout,
        pushConstantRangeCount = push_const_ranges.count.(u32),
        pPushConstantRanges = push_const_ranges.data,
    };
    vk_result := vkCreatePipelineLayout(vk_device, *create_info, null, *vk_pipeline_layout);
    assert_vk_result(vk_result);
}

create_shader_stage :: (spirv: [] u8, stage: VkShaderStageFlagBits) -> VkPipelineShaderStageCreateInfo {
    create_info := VkShaderModuleCreateInfo.{
        codeSize = spirv.count.(u32),
        pCode = spirv.data.(*u32),
    };

    vk_shader_module: VkShaderModule;
    vk_result := vkCreateShaderModule(vk_device, *create_info, null, *vk_shader_module);
    assert_vk_result(vk_result);

    stage_create_info := VkPipelineShaderStageCreateInfo.{
        stage = stage,
        module = vk_shader_module,
        pName = "main",
    };
    return stage_create_info;
}