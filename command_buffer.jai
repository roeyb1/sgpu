#scope_export

gpu_start_command_recording :: (queue_handle: Gpu_Queue) -> Gpu_Result, Gpu_Command_Buffer {
    // #TODO: should we do this on every command recording? uncertain.
    reclaim_completed_command_pools();

    queue := get_queue(queue_handle);

    arena := *cmd_pools[queue.global_index];

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

        _, pool := bucket_array_add(*arena.all_pools, .{
            vk_cmd_pool = new_pool,
            vk_cmd_buff = new_buffer,
        });
        array_add(*arena.available_pools, pool);
    }

    pool := pop(*arena.available_pools);
    // There should never be a null pool in the list of available pools.
    debug_assert(pool != null);
    pool.queue = queue_handle;

    // find an empty slot in the live pools list
    found, index := array_find(live_pools, null);
    // the list is preallocated to the maximum number of possible live command lists so this should never fail.
    debug_assert(found);

    live_pools[index] = pool;

    cmd_buff_handle := cast(Gpu_Command_Buffer) (pool.vk_cmd_buff);

    table_add(*cmd_buffer_indices, cmd_buff_handle, index);

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
        dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT,
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
    } else {
        vkCmdSetDepthTestEnable(vk_cmd_buff, VK_FALSE);
    }

    if desc.depth_mode & .WRITE != 0 {
        vkCmdSetDepthWriteEnable(vk_cmd_buff, VK_TRUE);
        vkCmdSetDepthBias(vk_cmd_buff, desc.depth_bias, desc.depth_bias_clamp, desc.depth_bias_slope_factor);
    } else {
        vkCmdSetDepthWriteEnable(vk_cmd_buff, VK_FALSE);
    }

    // #todo: set stencil state
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
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .COMPUTE_BIT, 2 * size_of(Gpu_Ptr), size_of(Gpu_Ptr), *data);
    vkCmdDispatch(vk_cmd_buff, dimensions[0], dimensions[1], dimensions[2]);
}

gpu_indirect_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions_gpu: Gpu_Ptr) -> Gpu_Result {
    // not yet tested
    vk_cmd_buff := get_cmd_buff(cmd);

    result, indirect_buffer, offset := get_buffer_and_offset(dimensions_gpu);
    return_if_error(result);

    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .COMPUTE_BIT, 2 * size_of(VkDeviceAddress), size_of(VkDeviceAddress), *data);
    vkCmdDispatchIndirect(vk_cmd_buff, indirect_buffer, offset);

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
        view := get_texture_view(desc.depth_target.view);
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

    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, 0, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, 1 * size_of(VkDeviceAddress), size_of(VkDeviceAddress), *pixel_data);

    vkCmdDraw(vk_cmd_buff, vertex_count, instance_count, 0, 0);
}

gpu_draw_indexed_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, index_count: u32, instance_count: u32, index_size: u32 = size_of(u32)) -> Gpu_Result {
    vk_cmd_buff := get_cmd_buff(cmd);

    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, 0, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, 1 * size_of(VkDeviceAddress), size_of(VkDeviceAddress), *pixel_data);

    result, index_buffer, offset := get_buffer_and_offset(index_data);
    return_if_error(result);

    if index_size != 4 && index_size != 2 then return .ERROR_INVALID_VERTEX_INDEX_SIZE;
    vkCmdBindIndexBuffer(vk_cmd_buff, index_buffer, offset.(VkDeviceSize), ifx index_size == 4 then .UINT32 else .UINT16);
    vkCmdDrawIndexed(vk_cmd_buff, index_count, instance_count, 0, 0, 0);

    return .SUCCESS;
}

gpu_draw_indexed_indirect :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, args: Gpu_Ptr) -> Gpu_Result {
    // #todo
}


/** Queue resource for deletion when this command buffer finishes execution */
gpu_enqueue_destroy :: (cmd: Gpu_Command_Buffer, gpu_ptr: Gpu_Ptr) {
    pool := get_pool(cmd);
    queue := get_queue(pool.queue);
    garbage_list := *garbage_allocations[queue.global_index];
    array_add(garbage_list, .{queue.timeline_value, gpu_ptr});
}

gpu_enqueue_destroy :: (cmd: Gpu_Command_Buffer, texture: Gpu_Texture) {
    pool := get_pool(cmd);
    queue := get_queue(pool.queue);
    garbage_list := *garbage_textures[queue.global_index];
    array_add(garbage_list, .{queue.timeline_value, texture});
}

#scope_module

MAX_COMMAND_POOLS :: 128;

Command_Pool :: struct {
    vk_cmd_pool: VkCommandPool;
    vk_cmd_buff: VkCommandBuffer;
    queue: Gpu_Queue;
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

Garbage_Allocation :: struct {
    // #todo: should we support multiple queues referencing this object or just a single one?
    queue_submit_timeline_value: u64;
    ptr: Gpu_Ptr;
}

Garbage_Texture :: struct {
    // #todo: should we support multiple queues referencing this object or just a single one?
    queue_submit_timeline_value: u64;
    handle: Gpu_Texture;
}

live_pools: [MAX_COMMAND_POOLS * queues.count] *Command_Pool;
cmd_buffer_indices: Table(Gpu_Command_Buffer, s64);

// #TODO: fixed size allocation but can resizeable count within that buffer.
garbage_pools: [queues.count] [..] Garbage_Command_Pool;

garbage_allocations: [queues.count] [..] Garbage_Allocation;
garbage_textures: [queues.count] [..] Garbage_Texture;

reclaim_completed_command_pools :: () {
    for * arena, queue_index : cmd_pools {
        queue := *queues[queue_index];
        current_timeline_value: u64;
        vk_result := vkGetSemaphoreCounterValue(vk_device, queue.timeline, *current_timeline_value);
        assert_vk_result(vk_result);

        for garbage_pools[queue_index] {
            if it.queue_submit_timeline_value < current_timeline_value {
                vk_result = vkResetCommandPool(vk_device, it.pool.vk_cmd_pool, 0);
                assert_vk_result(vk_result);

                array_add(*arena.available_pools, it.pool);
                remove it;
            }
        }
    }
}

collect_garbage_resources :: () {
    for * arena, queue_index : cmd_pools {
        queue := *queues[queue_index];
        current_timeline_value: u64;
        vk_result := vkGetSemaphoreCounterValue(vk_device, queue.timeline, *current_timeline_value);
        assert_vk_result(vk_result);

        for garbage_allocations[queue_index] {
            if it.queue_submit_timeline_value < current_timeline_value {
                gpu_free(it.ptr);

                remove it;
            }
        }
        for garbage_textures[queue_index] {
            if it.queue_submit_timeline_value < current_timeline_value {
                gpu_free(it.handle);

                remove it;
            }
        }
    }
}

get_cmd_buff :: (cmd_buff_handle: Gpu_Command_Buffer) -> VkCommandBuffer {
    return cmd_buff_handle.(VkCommandBuffer);
}

get_cmd_buff_index :: (cmd_buff_handle: Gpu_Command_Buffer) -> s64 {
    found, cmd_buff_index := table_find(*cmd_buffer_indices, cmd_buff_handle);
    assert(found);

    return cmd_buff_index;
}

Submit_Info :: struct {
    cmd_buff: Gpu_Command_Buffer;
    wait_semaphores: [] VkSemaphore = .[];
    signal_semaphores: [] VkSemaphore = .[];
    wait_timelines: [] Gpu_Timeline_Pair = .[];
    signal_timelines: [] Gpu_Timeline_Pair = .[];
}

submit_command_buffer :: (using submit_info: Submit_Info) {
    index := get_cmd_buff_index(cmd_buff);
    assert(index < live_pools.count);
    pool := live_pools[index];
    // #todo: propagate this error up.
    debug_assert(pool != null);

    vkEndCommandBuffer(pool.vk_cmd_buff);

    queue := get_queue(pool.queue);

    queue_timeline_value := atomic_add(*queue.timeline_value, 1) + 1; // atomic_add returns the previous value.

    auto_release_temp();
    push_allocator(temp);

    all_signal_values: [..] u64;
    all_signal_semaphores: [..] VkSemaphore;
    all_wait_values: [..] u64;
    all_wait_semaphores: [..] VkSemaphore;
    array_add(*all_signal_values, queue.timeline_value);
    array_add(*all_signal_semaphores, queue.timeline);
    for 0..signal_semaphores.count-1 {
        array_add(*all_signal_semaphores, signal_semaphores[it]);
        array_add(*all_signal_values, 0);
    }
    for signal_timelines {
        array_add(*all_signal_semaphores, get_semaphore(it.semaphore).vk_semaphore);
        array_add(*all_signal_values, it.value);
    }

    for 0..wait_semaphores.count-1 {
        array_add(*all_wait_semaphores, wait_semaphores[it]);
        array_add(*all_wait_values, 0);
    }
    for wait_timelines {
        array_add(*all_wait_semaphores, get_semaphore(it.semaphore).vk_semaphore);
        array_add(*all_wait_values, it.value);
    }

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
    vkQueueSubmit(queue.vk_queue, 1, *vk_submit_info, VK_NULL_HANDLE);

    live_pools[index] = null;
    array_add(*garbage_pools[queue.global_index], .{queue_timeline_value, pool});
    table_remove(*cmd_buffer_indices, cmd_buff);
}

get_pool :: (cmd_buff: Gpu_Command_Buffer) -> *Command_Pool {
    index := get_cmd_buff_index(cmd_buff);
    assert(index < live_pools.count);
    pool := live_pools[index];

    return pool;
}
