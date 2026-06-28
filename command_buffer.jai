#scope_export

gpu_start_command_recording :: (queue_handle: Gpu_Queue) -> Gpu_Result, Gpu_Command_Buffer {
    // #TODO: should we do this on every command recording? uncertain.
    reclaim_completed_command_pools();
    reclaim_garbage_resources();

    queue := get_queue(queue_handle);

    arena := *cmd_pools[queue.global_index];

    pool: *Command_Pool;
    {
        lock(*cmd_pool_locks[queue.global_index]);
        defer unlock(*cmd_pool_locks[queue.global_index]);

        if arena.available_pools.count == 0 {
            if arena.all_pools.count >= MAX_COMMAND_POOLS {
                return .ERROR_COMMAND_BUFFER_LIMIT_EXCEEDED, 0;
            }

            new_pool: VkCommandPool;

            create_info := VkCommandPoolCreateInfo.{
                flags = .TRANSIENT_BIT,
                queueFamilyIndex = queue.vk_family,
            };

            vk_result := vkCreateCommandPool(vk_device, *create_info, null, *new_pool);
            return_if_error(vk_result, 0);

            new_buffer: VkCommandBuffer;

            alloc_info := VkCommandBufferAllocateInfo.{
                commandPool = new_pool,
                level = .PRIMARY,
                commandBufferCount = 1,
            };

            vk_result = vkAllocateCommandBuffers(vk_device, *alloc_info, *new_buffer);
            return_if_error(vk_result, 0);

            _, new_cmd_pool := bucket_array_add(*arena.all_pools, .{
                vk_cmd_pool = new_pool,
                vk_cmd_buff = new_buffer,
            });
            array_add(*arena.available_pools, new_cmd_pool);
        }

        pool = pop(*arena.available_pools);
    }
    // There should never be a null pool in the list of available pools.
    debug_assert(pool != null);
    pool.queue = queue_handle;

    cmd_buff_handle := cast(Gpu_Command_Buffer) (pool.vk_cmd_buff);
    {
        lock(*live_pools_lock);
        defer unlock(*live_pools_lock);

        // find an empty slot in the live pools list
        found, index := array_find(live_pools, null);
        // the list is preallocated to the maximum number of possible live command lists so this should never fail.
        debug_assert(found);

        live_pools[index] = pool;
        table_add(*cmd_buffer_indices, cmd_buff_handle, index);
    }

    begin_info := VkCommandBufferBeginInfo.{
        flags = .ONE_TIME_SUBMIT_BIT
    };
    vk_result := vkBeginCommandBuffer(pool.vk_cmd_buff, *begin_info);
    return_if_error(vk_result, 0);

    return .SUCCESS, cmd_buff_handle;
}

gpu_submit :: (cmd_buff: Gpu_Command_Buffer, signals: [] Gpu_Timeline_Pair = .[], waits: [] Gpu_Timeline_Pair = .[]) {
    submit_command_buffer(.{cmd_buff = cmd_buff, signal_timelines = signals, wait_timelines = waits });
}

gpu_cmd_begin_debug_marker :: (cmd: Gpu_Command_Buffer, label: string) {
    #if DEBUG_MARKERS {
        label_info := VkDebugUtilsLabelEXT.{
            pLabelName = to_c_string(label,, temp),
        };
        vkCmdBeginDebugUtilsLabelEXT(get_cmd_buff(cmd), *label_info);
    }
}

gpu_cmd_end_debug_marker :: (cmd: Gpu_Command_Buffer) {
    #if DEBUG_MARKERS then vkCmdEndDebugUtilsLabelEXT(get_cmd_buff(cmd));
}

gpu_scoped_debug_label :: (cmd: Gpu_Command_Buffer, label: string) #expand {
    gpu_cmd_begin_debug_marker(cmd, label);
    `defer gpu_cmd_end_debug_marker(cmd);
}

gpu_memcpy :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, num_bytes: s64) -> Gpu_Result {
    cmd_buff := get_cmd_buff(cmd);

    dest_found, dest_alloc_range := find_memory_range(dest);
    source_found, src_alloc_range := find_memory_range(src);

    if dest_found != .SUCCESS then return .ERROR_OUT_OF_BOUNDS;
    if source_found != .SUCCESS then return .ERROR_OUT_OF_BOUNDS;

    // ensure the copy region is valid for both memory ranges.
    assert(dest + num_bytes.(Gpu_Ptr) <= dest_alloc_range.end);
    assert(src + num_bytes.(Gpu_Ptr) <= src_alloc_range.end);

    found_dest, dest_alloc := table_find(*gpu_allocations, dest_alloc_range.start);
    if !found_dest then return .ERROR_OUT_OF_BOUNDS;
    found_src, src_alloc := table_find(*gpu_allocations, src_alloc_range.start);
    if !found_src then return .ERROR_OUT_OF_BOUNDS;

    region := VkBufferCopy.{
        dstOffset = (dest - dest_alloc.gpu_ptr).(u64),
        srcOffset = (src - src_alloc.gpu_ptr).(u64),
        size = num_bytes.(u64),
    };

    vkCmdCopyBuffer(cmd_buff, src_alloc.vk_buffer, dest_alloc.vk_buffer, 1, *region);

    return .SUCCESS;
}

gpu_copy_to_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Texture, src: Gpu_Ptr, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) -> Gpu_Result {
    texture := get_texture(dest);
    if !texture then return .ERROR_INVALID_TEXTURE;
    vk_cmd_buff := get_cmd_buff(cmd);

    result, src_buffer, src_offset := get_buffer_and_offset(src);
    return_if_error(result);

    base_layer := layer_slice[0];
    subresource := VkImageSubresourceLayers.{
        aspectMask = get_image_aspect_mask(texture.desc.format),
        mipLevel = mip,
        baseArrayLayer = base_layer,
        layerCount = min(layer_slice[1], texture.desc.layer_count - base_layer),
    };

    copy_region := VkBufferImageCopy.{
        bufferOffset = src_offset.(VkDeviceSize),
        bufferRowLength = 0,
        bufferImageHeight = 0,
        imageOffset = VkOffset3D.{},
        imageSubresource = subresource,
        imageExtent = VkExtent3D.{texture.desc.dimensions[0], texture.desc.dimensions[1], texture.desc.dimensions[2]}
    };

    vkCmdCopyBufferToImage(vk_cmd_buff, src_buffer, texture.vk_image, .GENERAL, 1, *copy_region);
    return .SUCCESS;
}

gpu_copy_to_texture :: (cmd: Gpu_Command_Buffer, dest_view_handle: Gpu_Texture_View, src_view_handle: Gpu_Texture_View) -> Gpu_Result {
    dest_view := get_texture_view(dest_view_handle);
    src_view := get_texture_view(src_view_handle);

    if !dest_view || !src_view then return .ERROR_INVALID_TEXTURE_VIEW;

    return gpu_copy_to_texture(cmd, dest_view.texture, src_view.texture);
}

gpu_copy_to_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Texture, src: Gpu_Texture, base_layer: u32 = 0, layer_count: u32 = 0) -> Gpu_Result {
    dest_texture := get_texture(dest);
    src_texture := get_texture(src);
    if !dest_texture || !src_texture then return .ERROR_INVALID_TEXTURE;
    vk_cmd_buff := get_cmd_buff(cmd);
    actual_layer_count := ifx layer_count == 0 then src_texture.desc.layer_count else layer_count;
    region := VkImageCopy2.{
        srcSubresource = .{
            aspectMask = get_image_aspect_mask(src_texture.desc.format),
            mipLevel = 0,
            baseArrayLayer = base_layer,
            layerCount = actual_layer_count,
        },
        dstSubresource = .{
            aspectMask = get_image_aspect_mask(dest_texture.desc.format),
            mipLevel = 0,
            baseArrayLayer = base_layer,
            layerCount = actual_layer_count,
        },
        srcOffset = .{ x = 0, y = 0, z = 0 },
        dstOffset = .{ x = 0, y = 0, z = 0 },
        extent = .{
            width = src_texture.desc.dimensions[0],
            height = src_texture.desc.dimensions[1],
            depth = src_texture.desc.dimensions[2],
        },
    };
    copy := VkCopyImageInfo2.{
        srcImage = src_texture.vk_image,
        srcImageLayout = .GENERAL,
        dstImage = dest_texture.vk_image,
        dstImageLayout = .GENERAL,
        regionCount = 1,
        pRegions = *region,
    };
    vkCmdCopyImage2(vk_cmd_buff, *copy);
    return .SUCCESS;
}

gpu_blit_image :: (cmd: Gpu_Command_Buffer, dst: Gpu_Texture, src: Gpu_Texture, src_mip: u32 = 0, dst_mip: u32 = 0, filter: VkFilter = .LINEAR) -> Gpu_Result {
    dst_texture := get_texture(dst);
    src_texture := get_texture(src);
    if !dst_texture || !src_texture then return .ERROR_INVALID_TEXTURE;

    vk_cmd_buff := get_cmd_buff(cmd);

    src_w := max(1, src_texture.desc.dimensions[0] >> src_mip);
    src_h := max(1, src_texture.desc.dimensions[1] >> src_mip);
    dst_w := max(1, dst_texture.desc.dimensions[0] >> dst_mip);
    dst_h := max(1, dst_texture.desc.dimensions[1] >> dst_mip);

    blit_region := VkImageBlit2.{
        srcSubresource = .{
            aspectMask = get_image_aspect_mask(src_texture.desc.format),
            mipLevel = src_mip,
            baseArrayLayer = 0,
            layerCount = src_texture.desc.layer_count,
        },
        srcOffsets = .[.{x = 0, y = 0, z = 0}, .{x = xx src_w, y = xx src_h, z = 1}],
        dstSubresource = .{
            aspectMask = get_image_aspect_mask(dst_texture.desc.format),
            mipLevel = dst_mip,
            baseArrayLayer = 0,
            layerCount = dst_texture.desc.layer_count,
        },
        dstOffsets = .[.{x = 0, y = 0, z = 0}, .{x = xx dst_w, y = xx dst_h, z = 1}],
    };

    blit_info := VkBlitImageInfo2.{
        srcImage = src_texture.vk_image,
        srcImageLayout = .GENERAL,
        dstImage = dst_texture.vk_image,
        dstImageLayout = .GENERAL,
        regionCount = 1,
        pRegions = *blit_region,
        filter = filter,
    };

    vkCmdBlitImage2(vk_cmd_buff, *blit_info);
    return .SUCCESS;
}

gpu_clear_texture :: (cmd: Gpu_Command_Buffer, view_handle: Gpu_Texture_View, clear_color: Gpu_Color_Value) -> Gpu_Result {
    view := get_texture_view(view_handle);
    if !view then return .ERROR_INVALID_TEXTURE_VIEW;

    return gpu_clear_texture(cmd, view.texture, clear_color);
}

gpu_clear_texture :: (cmd: Gpu_Command_Buffer, texture_handle: Gpu_Texture, clear_color: Gpu_Color_Value) -> Gpu_Result {
    texture := get_texture(texture_handle);
    if !texture then return .ERROR_INVALID_TEXTURE;

    vk_cmd_buff := get_cmd_buff(cmd);

    // #todo: support clearing specific mip/array ranges.
    range := VkImageSubresourceRange.{
        aspectMask = get_image_aspect_mask(texture.desc.format),
        baseMipLevel = 0,
        levelCount = texture.desc.mip_count,
        baseArrayLayer = 0,
        layerCount = texture.desc.layer_count,
    };

    vkCmdClearColorImage(vk_cmd_buff, texture.vk_image, .GENERAL, (*clear_color).(*VkClearColorValue), 1, *range);

    return .SUCCESS;
}

gpu_barrier :: (cmd: Gpu_Command_Buffer, before: Stage, after: Stage) {
    cmd_buff := get_cmd_buff(cmd);

    // the barrier model in this api is based on the assumption that most gpu caches are coherent in the modern day.
    // Thus eliminating the need for the vast majority of memory barriers and simplifying the barrier model to execution only.
    // I have yet to thoroughly test this and it is possible I may need to pivot that idea. However, adding resource state
    // tracking is a huge api bloat so I plan to try this first.
    memory_barrier := VkMemoryBarrier2.{
        srcStageMask = before.(VkPipelineStageFlags2),
        dstStageMask = after.(VkPipelineStageFlags2),
        srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT,
        dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
    };

    dep_info := VkDependencyInfo.{
        memoryBarrierCount = 1,
        pMemoryBarriers = *memory_barrier,
    };

    vkCmdPipelineBarrier2(cmd_buff, *dep_info);
}

gpu_set_pipeline :: (cmd: Gpu_Command_Buffer, pipeline_handle: Gpu_Pipeline) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);
    pipeline := pool_get(live_pipelines, pipeline_handle);
    if !pipeline then return .ERROR_INVALID_PIPELINE;

    bind_point: VkPipelineBindPoint = ifx pipeline.type == .GRAPHICS then .GRAPHICS else .COMPUTE;

    vkCmdBindPipeline(vk_cmd_buff, bind_point, pipeline.vk_pipeline);
    // #todo: Do we need to rebind this every time? All the pipelines share the same pipeline layout so the binding is compatible.
    bind_descriptors(vk_cmd_buff, bind_point);

    return .SUCCESS;
}

gpu_set_depth_stencil_state :: (cmd: Gpu_Command_Buffer, desc: Gpu_Depth_Stencil_Desc) {
    vk_cmd_buff := get_cmd_buff(cmd);
    if desc.depth_test != .NEVER {
        vkCmdSetDepthTestEnable(vk_cmd_buff, VK_TRUE);
        vkCmdSetDepthCompareOp(vk_cmd_buff, desc.depth_test.(VkCompareOp));

		if desc.depth_bias != 0 || desc.depth_bias_slope_factor != 0 {
			vkCmdSetDepthBiasEnable(vk_cmd_buff, VK_TRUE); 
			vkCmdSetDepthBias(vk_cmd_buff, desc.depth_bias, desc.depth_bias_clamp, desc.depth_bias_slope_factor);
		}
    } else {
        vkCmdSetDepthTestEnable(vk_cmd_buff, VK_FALSE);
    }

    if desc.depth_mode & .WRITE != 0 {
        vkCmdSetDepthWriteEnable(vk_cmd_buff, VK_TRUE);
    } else {
        vkCmdSetDepthWriteEnable(vk_cmd_buff, VK_FALSE);
    }

    has_stencil := desc.stencil_front.test != .NEVER || desc.stencil_back.test != .NEVER;
    if has_stencil {
        vkCmdSetStencilTestEnable(vk_cmd_buff, VK_TRUE);

        vkCmdSetStencilOp(vk_cmd_buff, .FACE_FRONT_BIT,
            desc.stencil_front.fail_op.(VkStencilOp),
            desc.stencil_front.pass_op.(VkStencilOp),
            desc.stencil_front.depth_fail_op.(VkStencilOp),
            desc.stencil_front.test.(VkCompareOp));

        vkCmdSetStencilOp(vk_cmd_buff, .FACE_BACK_BIT,
            desc.stencil_back.fail_op.(VkStencilOp),
            desc.stencil_back.pass_op.(VkStencilOp),
            desc.stencil_back.depth_fail_op.(VkStencilOp),
            desc.stencil_back.test.(VkCompareOp));

        vkCmdSetStencilCompareMask(vk_cmd_buff, .FRONT_AND_BACK, desc.stencil_read_mask.(u32));
        vkCmdSetStencilWriteMask(vk_cmd_buff, .FRONT_AND_BACK, desc.stencil_write_mask.(u32));
        vkCmdSetStencilReference(vk_cmd_buff, .FACE_FRONT_BIT, desc.stencil_front.reference.(u32));
        vkCmdSetStencilReference(vk_cmd_buff, .FACE_BACK_BIT, desc.stencil_back.reference.(u32));
    } else {
        vkCmdSetStencilTestEnable(vk_cmd_buff, VK_FALSE);
    }
}

gpu_set_blend_state :: (cmd: Gpu_Command_Buffer, state: Gpu_Blend_State) {

}

gpu_set_viewport :: (cmd: Gpu_Command_Buffer, viewport: Viewport) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdSetViewport(vk_cmd_buff, 0, 1, (*viewport).(*VkViewport));
}
gpu_set_viewports :: (cmd: Gpu_Command_Buffer, viewports: [] Viewport) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdSetViewport(vk_cmd_buff, 0, viewports.count.(u32), (viewports.data).(*VkViewport));
}

gpu_set_scissors :: (cmd: Gpu_Command_Buffer, rects: [] Rect_2D) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdSetScissor(vk_cmd_buff, 0, rects.count.(u32), (rects.data).(*VkRect2D));
}

gpu_set_scissor :: (cmd: Gpu_Command_Buffer, rect: Rect_2D) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdSetScissor(vk_cmd_buff, 0, 1, (*rect).(*VkRect2D));
}

gpu_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) {
    vk_cmd_buff := get_cmd_buff(cmd);

    compute_offset := get_stage_offset(.COMPUTE);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .COMPUTE_BIT, compute_offset, size_of(Gpu_Ptr), *data);
    vkCmdDispatch(vk_cmd_buff, dimensions[0], dimensions[1], dimensions[2]);
}

gpu_indirect_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions_gpu: Gpu_Ptr) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    result, indirect_buffer, offset := get_buffer_and_offset(dimensions_gpu);
    return_if_error(result);

    compute_offset := get_stage_offset(.COMPUTE);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .COMPUTE_BIT, compute_offset, size_of(VkDeviceAddress), *data);
    vkCmdDispatchIndirect(vk_cmd_buff, indirect_buffer, offset.(u64));

    return .SUCCESS;
}

gpu_begin_render_pass :: (cmd: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    color_attachments: [MAX_ATTACHMENTS] VkRenderingAttachmentInfo;

    render_area: VkRect2D = .{offset = .{0, 0}};
    layer_count: u32 = 1;
    for desc.color_targets {
        view := get_texture_view(it.view);
        if view == null {
            return .ERROR_INVALID_TEXTURE;
        }
        texture := get_texture(view.texture);
        render_area.extent.width = texture.desc.dimensions[0];
        render_area.extent.height = texture.desc.dimensions[1];
        layer_count = texture.desc.layer_count;

        color_attachments[it_index] = .{
            imageView = view.vk_view,
            imageLayout = .GENERAL,
            resolveMode = .NONE,
            loadOp = it.load_op.(VkAttachmentLoadOp),
            storeOp = it.store_op.(VkAttachmentStoreOp),
            clearValue.color = cast,force(VkClearColorValue) it.clear_color,
        };
    }

    render_info := VkRenderingInfo.{
        layerCount = layer_count,
        colorAttachmentCount = desc.color_targets.count.(u32),
        pColorAttachments = color_attachments.data,
    };

    depth_attachment: VkRenderingAttachmentInfo;
    if desc.depth_target.view != 0 {
        view := get_texture_view(desc.depth_target.view);
        if view == null {
            return .ERROR_INVALID_TEXTURE;
        }
        texture := get_texture(view.texture);
        render_area.extent.width = texture.desc.dimensions[0];
        render_area.extent.height = texture.desc.dimensions[1];

        depth_attachment = .{
            imageView = view.vk_view,
            imageLayout = .GENERAL,
            resolveMode = .NONE,
            loadOp = desc.depth_target.load_op.(VkAttachmentLoadOp),
            storeOp = desc.depth_target.store_op.(VkAttachmentStoreOp),
            clearValue.depthStencil.depth = desc.depth_target.clear_value.depth,
        };
        render_info.pDepthAttachment = *depth_attachment;
    }

    stencil_attachment: VkRenderingAttachmentInfo;
    if desc.stencil_target.view != 0 {
        view := get_texture_view(desc.stencil_target.view);
        if view == null {
            return .ERROR_INVALID_TEXTURE;
        }
        texture := get_texture(view.texture);
        render_area.extent.width = texture.desc.dimensions[0];
        render_area.extent.height = texture.desc.dimensions[1];

        stencil_attachment = VkRenderingAttachmentInfo.{
            imageView = view.vk_view,
            imageLayout = .GENERAL,
            resolveMode = .NONE,
            loadOp = desc.stencil_target.load_op.(VkAttachmentLoadOp),
            storeOp = desc.stencil_target.store_op.(VkAttachmentStoreOp),
            clearValue.depthStencil.stencil = desc.stencil_target.clear_value.stencil,
        };
        render_info.pStencilAttachment = *stencil_attachment;
    }

    render_info.renderArea = render_area;

    vkCmdBeginRendering(vk_cmd_buff, *render_info);

    // #todo: I don't want to require users to have to set these for every draw since the majority of cases will just be doing something like this.
    // should we instead detect if users have manually set these values and if not, set something behind their back if they start drawing?
    viewport := VkViewport.{x = 0, y = 0, width = xx render_area.extent.width, height = xx render_area.extent.height, minDepth = 0, maxDepth = 1};
    vkCmdSetViewport(vk_cmd_buff, 0, 1, *viewport);
    vkCmdSetScissor(vk_cmd_buff, 0, 1, *render_area);

    return .SUCCESS;
}

gpu_end_render_pass :: (cmd: Gpu_Command_Buffer) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdEndRendering(vk_cmd_buff);
}

gpu_draw_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, vertex_count: u32, instance_count: u32) {
    vk_cmd_buff := get_cmd_buff(cmd);

    vertex_offset := get_stage_offset(.VERTEX);
    pixel_offset := get_stage_offset(.PIXEL);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, vertex_offset, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, pixel_offset, size_of(VkDeviceAddress), *pixel_data);

    vkCmdDraw(vk_cmd_buff, vertex_count, instance_count, 0, 0);
}

gpu_draw_indexed_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, index_count: u32, instance_count: u32, index_size: u32 = size_of(u32)) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    vertex_offset := get_stage_offset(.VERTEX);
    pixel_offset := get_stage_offset(.PIXEL);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, vertex_offset, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, pixel_offset, size_of(VkDeviceAddress), *pixel_data);

    result, index_buffer, offset := get_buffer_and_offset(index_data);
    return_if_error(result);

    if index_size != 4 && index_size != 2 then return .ERROR_INVALID_VERTEX_INDEX_SIZE;
    vkCmdBindIndexBuffer(vk_cmd_buff, index_buffer, offset.(VkDeviceSize), ifx index_size == 4 then .UINT32 else .UINT16);
    vkCmdDrawIndexed(vk_cmd_buff, index_count, instance_count, 0, 0, 0);

    return .SUCCESS;
}

gpu_draw_indirect :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, args: Gpu_Ptr) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    vertex_offset := get_stage_offset(.VERTEX);
    pixel_offset  := get_stage_offset(.PIXEL);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, vertex_offset, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, pixel_offset,  size_of(VkDeviceAddress), *pixel_data);

    result, indirect_buffer, indirect_offset := get_buffer_and_offset(args);
    return_if_error(result);

    vkCmdDrawIndirect(vk_cmd_buff, indirect_buffer, indirect_offset.(u64), 1, size_of(VkDrawIndirectCommand));

    return .SUCCESS;
}

gpu_draw_indexed_indirect :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, args: Gpu_Ptr) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    vertex_offset := get_stage_offset(.VERTEX);
    pixel_offset := get_stage_offset(.PIXEL);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, vertex_offset, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, pixel_offset, size_of(VkDeviceAddress), *pixel_data);

    result, index_buffer, offset := get_buffer_and_offset(index_data);
    return_if_error(result);

    vkCmdBindIndexBuffer(vk_cmd_buff, index_buffer, offset.(VkDeviceSize), .UINT32);

    result2, indirect_buffer, indirect_offset := get_buffer_and_offset(args);
    return_if_error(result2);

    vkCmdDrawIndexedIndirect(vk_cmd_buff, indirect_buffer, indirect_offset.(u64), 1, size_of(Gpu_Draw_Args));

    return .SUCCESS;
}

gpu_draw_meshlets :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) -> Gpu_Result {
    if !vkCmdDrawMeshTasksEXT then return .ERROR_MISSING_OPTIONAL_EXTENSION;

    vk_cmd_buff := get_cmd_buff(cmd);

    task_offset := get_stage_offset(.TASK);
    mesh_offset := get_stage_offset(.MESH);
    pixel_offset := get_stage_offset(.PIXEL);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .TASK_BIT_EXT, task_offset, size_of(VkDeviceAddress), *data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .MESH_BIT_EXT, mesh_offset, size_of(VkDeviceAddress), *data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, pixel_offset, size_of(VkDeviceAddress), *data);

    vkCmdDrawMeshTasksEXT(vk_cmd_buff, dimensions[0], dimensions[1], dimensions[2]);
    return .SUCCESS;
}


/** Queue resource for deletion after this command buffer's submission completes AND all
 * already-submitted work on other queues completes.
 *
 * Contract: the caller must ensure no NEW work referencing this resource will be submitted
 * after this call, apart from `cmd` itself. The destroy waits for:
 *   - `cmd`'s submission (not yet assigned a timeline value at enqueue time)
 *   - every other queue's latest-submitted timeline value at submit time of `cmd`
 *
 * Staging on the pool (rather than snapshotting and appending globally now) is what makes
 * this correct: at enqueue time we don't yet know the signal value `cmd` will be assigned,
 * so we defer snapshot + global-append to submit_command_buffer.
 */
gpu_enqueue_destroy :: (cmd: Gpu_Command_Buffer, gpu_ptr: Gpu_Ptr) {
    pool := get_pool(cmd);
    // No lock needed: a given pool is owned by a single recording thread between
    // gpu_start_command_recording and gpu_submit, so pool.staged_* is unshared during that window.
    array_add(*pool.staged_allocations, gpu_ptr,, cpu_allocator);
}

gpu_enqueue_destroy :: (cmd: Gpu_Command_Buffer, texture: Gpu_Texture) {
    pool := get_pool(cmd);
    array_add(*pool.staged_textures, texture,, cpu_allocator);
}

#scope_module

MAX_COMMAND_POOLS :: 128;

Command_Pool :: struct {
    vk_cmd_pool: VkCommandPool;
    vk_cmd_buff: VkCommandBuffer;
    queue: Gpu_Queue;
    last_submit_timeline_value: u64;

    // Resources enqueued for destruction while this pool is being recorded. Promoted into
    // the global garbage lists at submit time, once we know the signal value for this pool's
    // submission (required so the destroy waits for the in-progress recording to actually run).
    staged_allocations: [..] Gpu_Ptr;
    staged_textures:    [..] Gpu_Texture;
}

// Per-queue timeline snapshot used to gate resource destruction. A resource is safe to free
// once every queue's GPU-completed timeline value is >= the snapshot taken at enqueue time.
Garbage_Allocation :: struct {
    wait_values: [queues.count] u64;
    gpu_ptr: Gpu_Ptr;
}
Garbage_Texture :: struct {
    wait_values: [queues.count] u64;
    texture: Gpu_Texture;
}

Command_Pool_Arena :: struct {
    // bucket array is used here for pointer stability and to ensure stability of all elements after removal.
    // this could just be a xar + free list.
    all_pools: Bucket_Array(Command_Pool, 32);
    available_pools: [..] *Command_Pool;
}

cmd_pools: [queues.count] Command_Pool_Arena;

Garbage_Command_Pool :: struct {
    queue_submit_timeline_value: u64;
    pool: *Command_Pool;
}

live_pools: [MAX_COMMAND_POOLS * queues.count] *Command_Pool;
cmd_buffer_indices: Table(Gpu_Command_Buffer, s64);
live_pools_lock: Mutex;

// #TODO: fixed size allocation but can resizeable count within that buffer.
garbage_pools: [queues.count] [..] Garbage_Command_Pool;

// Global garbage lists (not per-pool, not per-queue). A resource may have been used by
// command buffers across multiple queues, so its destruction must wait for ALL of those
// queues to have completed the timeline values recorded at enqueue time.
garbage_allocations: [..] Garbage_Allocation;
garbage_textures:    [..] Garbage_Texture;
garbage_resources_lock: Mutex;

cmd_pool_locks:     [queues.count] Mutex;  // protects cmd_pools[i] and garbage_pools[i]

reclaim_completed_command_pools :: () {
    for * arena, queue_index : cmd_pools {
        queue := *queues[queue_index];
        current_timeline_value: u64 = U64_MAX; // sentinel so an ignored error is obvious
        vk_result := vkGetSemaphoreCounterValue(vk_device, queue.timeline, *current_timeline_value);
        assert_vk_result(vk_result);

        lock(*cmd_pool_locks[queue_index]);
        defer unlock(*cmd_pool_locks[queue_index]);

        for garbage_pools[queue_index] {
            if it.queue_submit_timeline_value <= current_timeline_value {
                pool := it.pool;

                pool.last_submit_timeline_value = 0;

                vk_result = vkResetCommandPool(vk_device, pool.vk_cmd_pool, 0);
                assert_vk_result(vk_result);

                array_add(*arena.available_pools, pool);
                remove it;
            }
        }
    }
}

reclaim_garbage_resources :: () {
    completed: [queues.count] u64;
    for q : 0..queues.count-1 {
        vk_result := vkGetSemaphoreCounterValue(vk_device, queues[q].timeline, *completed[q]);
        assert_vk_result(vk_result);
    }

    lock(*garbage_resources_lock);
    defer unlock(*garbage_resources_lock);

    for * garbage_allocations {
        ready := true;
        for q : 0..queues.count-1 if it.wait_values[q] > completed[q] { ready = false; break; }
        if ready {
            gpu_free(it.gpu_ptr);
            remove it;
        }
    }
    for * garbage_textures {
        ready := true;
        for q : 0..queues.count-1 if it.wait_values[q] > completed[q] { ready = false; break; }
        if ready {
            gpu_free(it.texture);
            remove it;
        }
    }
}

collect_garbage_resources :: () {
    reclaim_completed_command_pools();
    reclaim_garbage_resources();
}

get_cmd_buff :: (cmd_buff_handle: Gpu_Command_Buffer) -> VkCommandBuffer {
    return cmd_buff_handle.(VkCommandBuffer);
}

Submit_Info :: struct {
    cmd_buff: Gpu_Command_Buffer;
    wait_semaphores: [] VkSemaphore = .[];
    signal_semaphores: [] VkSemaphore = .[];
    wait_timelines: [] Gpu_Timeline_Pair = .[];
    signal_timelines: [] Gpu_Timeline_Pair = .[];
}

submit_command_buffer :: (using submit_info: Submit_Info) {
    index: s64;
    pool: *Command_Pool;
    {
        lock(*live_pools_lock);
        defer unlock(*live_pools_lock);

        found, table_index := table_find(*cmd_buffer_indices, cmd_buff);
        assert(found);
        index = table_index;
        assert(index < live_pools.count);
        pool = live_pools[index];
        // #todo: propagate this error up.
        debug_assert(pool != null);
    }

    vkEndCommandBuffer(pool.vk_cmd_buff);

    queue := get_queue(pool.queue);

    auto_release_temp();
    push_allocator(temp);

    all_signal_values: [..] u64;
    all_signal_semaphores: [..] VkSemaphore;
    all_wait_values: [..] u64;
    all_wait_semaphores: [..] VkSemaphore;

    for signal_semaphores {
        array_add(*all_signal_semaphores, it);
        array_add(*all_signal_values, 0);
    }
    for signal_timelines {
        array_add(*all_signal_semaphores, get_semaphore(it.semaphore).vk_semaphore);
        array_add(*all_signal_values, it.value);
    }

    for wait_semaphores {
        array_add(*all_wait_semaphores, it);
        array_add(*all_wait_values, 0);
    }
    for wait_timelines {
        array_add(*all_wait_semaphores, get_semaphore(it.semaphore).vk_semaphore);
        array_add(*all_wait_values, it.value);
    }

    queue_timeline_value: u64;
    {
        queue.timeline_value += 1;
        queue_timeline_value = queue.timeline_value;

        array_add(*all_signal_values, queue_timeline_value);
        array_add(*all_signal_semaphores, queue.timeline);

        timeline_info := VkTimelineSemaphoreSubmitInfo.{
            waitSemaphoreValueCount = all_wait_values.count.(u32),
            pWaitSemaphoreValues = all_wait_values.data,
            signalSemaphoreValueCount = all_signal_values.count.(u32),
            pSignalSemaphoreValues = all_signal_values.data,
        };

        wait_stages := VkPipelineStageFlagBits.TOP_OF_PIPE_BIT;
        cmd_buffers := VkCommandBuffer.[pool.vk_cmd_buff];
        vk_submit_info := VkSubmitInfo.{
            pNext = *timeline_info,
            commandBufferCount = cmd_buffers.count.(u32),
            pCommandBuffers = cmd_buffers.data,
            signalSemaphoreCount = all_signal_semaphores.count.(u32),
            pSignalSemaphores = all_signal_semaphores.data,
            waitSemaphoreCount = all_wait_semaphores.count.(u32),
            pWaitSemaphores = all_wait_semaphores.data,
            pWaitDstStageMask = *wait_stages,
        };
        submit_result := vkQueueSubmit(queue.vk_queue, 1, *vk_submit_info, VK_NULL_HANDLE);

        pool.last_submit_timeline_value = queue_timeline_value;
    }

    // Promote staged destroys into the global garbage lists now that we know this submission's
    // signal value. wait_values[this_queue] = queue_timeline_value (the value the GPU will
    // signal when this command buffer finishes); wait_values[other_queue] = that queue's
    // latest submitted value (already committed, safe to read).
    if pool.staged_allocations.count || pool.staged_textures.count {
        wait_values: [queues.count] u64;
        for q : 0..queues.count-1 wait_values[q] = queues[q].timeline_value;
        wait_values[queue.global_index] = queue_timeline_value;

        lock(*garbage_resources_lock);
        defer unlock(*garbage_resources_lock);

        for pool.staged_allocations {
            entry: Garbage_Allocation;
            entry.wait_values = wait_values;
            entry.gpu_ptr = it;
            array_add(*garbage_allocations, entry,, cpu_allocator);
        }
        for pool.staged_textures {
            entry: Garbage_Texture;
            entry.wait_values = wait_values;
            entry.texture = it;
            array_add(*garbage_textures, entry,, cpu_allocator);
        }
        array_reset_keeping_memory(*pool.staged_allocations);
        array_reset_keeping_memory(*pool.staged_textures);
    }

    // Publish the pool transition (live -> garbage) atomically under cmd_pool_lock.
    // Holding cmd_pool_lock here prevents reclaim_completed_command_pools from observing
    // the pool, recycling it, and handing it back to a new recording thread (which would
    // then do table_add on the same VkCommandBuffer key before we got to table_remove).
    {
        lock(*cmd_pool_locks[queue.global_index]);
        defer unlock(*cmd_pool_locks[queue.global_index]);

        {
            lock(*live_pools_lock);
            defer unlock(*live_pools_lock);
            live_pools[index] = null;
            table_remove(*cmd_buffer_indices, cmd_buff);
        }

        array_add(*garbage_pools[queue.global_index], .{queue_timeline_value, pool});
    }
}

get_pool :: (cmd_buff: Gpu_Command_Buffer) -> *Command_Pool {
    lock(*live_pools_lock);
    defer unlock(*live_pools_lock);

    found, index := table_find(*cmd_buffer_indices, cmd_buff);
    assert(found);
    assert(index < live_pools.count);
    pool := live_pools[index];

    return pool;
}
