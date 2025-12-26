#scope_export

gpu_start_command_recording :: (queue_handle: Gpu_Queue) -> Gpu_Command_Buffer {
    // #TODO: should we do this on every command recording? uncertain.
    // currently this is the only thing that happens in collect garbage.
    // That will likely change so this will be less of a win but right
    // now it eliminates the need for collecting garbage.
    // It would also be much more efficient to bulk all the deletions at the same time
    // rather than querying the timeline semaphores and comparing on every command recorder.
    // How often are commands really recorded per frame? Not much, I doubt that overhead is significant.
    reclaim_completed_command_pools();

    queue := get_queue(queue_handle);

    arena := *cmd_pools[queue.global_index];

    if arena.available_pools.count == 0 {
        assert(arena.all_pools.count < MAX_COMMAND_POOLS);

        new_pool: VkCommandPool;

        create_info := VkCommandPoolCreateInfo.{
            flags = .TRANSIENT_BIT,
            queueFamilyIndex = queue.vk_family,
        };

        vk_result := vkCreateCommandPool(vk_device, *create_info, null, *new_pool);
        assert_vk_result(vk_result);
        
        new_buffer: VkCommandBuffer;

        alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = new_pool,
            level = .PRIMARY,
            commandBufferCount = 1,
        };

        vk_result = vkAllocateCommandBuffers(vk_device, *alloc_info, *new_buffer);
        assert_vk_result(vk_result);

        _, pool := bucket_array_add(*arena.all_pools, .{
            vk_cmd_pool = new_pool,
            vk_cmd_buff = new_buffer,
        });
        array_add(*arena.available_pools, pool);
    }

    pool := pop(*arena.available_pools);
    assert(pool != null);
    pool.queue = queue_handle;

    // find an empty slot in the live pools list
    found, index := array_find(live_pools, null);
    // the list is preallocated to the maximum number of possible live command lists so this should never fail.
    assert(found);

    live_pools[index] = pool;

    cmd_buff_handle := cast(Gpu_Command_Buffer) (pool.vk_cmd_buff);

    table_add(*cmd_buffer_indices, cmd_buff_handle, index);

    begin_info := VkCommandBufferBeginInfo.{
        flags = .ONE_TIME_SUBMIT_BIT
    };
    vkBeginCommandBuffer(pool.vk_cmd_buff, *begin_info);

    return cmd_buff_handle;
}

gpu_submit :: (cmd_buff: Gpu_Command_Buffer, signals: [] Gpu_Timeline_Pair = .[], waits: [] Gpu_Timeline_Pair = .[]) {
    submit_command_buffer(.{cmd_buff = cmd_buff, signal_timelines = signals, wait_timelines = waits });
}

gpu_memcpy :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, num_bytes: s64) {
    cmd_buff := get_cmd_buff(cmd);

    dest_alloc_range := find_memory_range(dest);
    src_alloc_range := find_memory_range(src);

    assert(dest_alloc_range.start != 0);
    assert(src_alloc_range.start != 0);

    // ensure the copy region is valid for both memory ranges.
    assert(dest + num_bytes.(Gpu_Ptr) <= dest_alloc_range.end);
    assert(src + num_bytes.(Gpu_Ptr) <= src_alloc_range.end);

    found_dest, dest_alloc := table_find(*gpu_allocations, dest_alloc_range.start);
    assert(found_dest);
    found_src, src_alloc := table_find(*gpu_allocations, src_alloc_range.start);
    assert(found_src);

    region := VkBufferCopy.{
        dstOffset = (dest - dest_alloc.gpu_ptr).(u64),
        srcOffset = (src - src_alloc.gpu_ptr).(u64),
        size = num_bytes.(u64),
    };

    vkCmdCopyBuffer(cmd_buff, src_alloc.vk_buffer, dest_alloc.vk_buffer, 1, *region);
}

gpu_copy_to_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Texture, src: Gpu_Ptr, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) {
    texture := get_texture(dest);
    assert(texture != null);
    vk_cmd_buff := get_cmd_buff(cmd);

    src_buffer, src_offset := get_buffer_and_offset(src);
    assert(src_buffer != VK_NULL_HANDLE);

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

gpu_set_pipeline :: (cmd: Gpu_Command_Buffer, pipeline_handle: Gpu_Pipeline) {
    vk_cmd_buff := get_cmd_buff(cmd);
    pipeline := pool_get(live_pipelines, pipeline_handle);

    bind_point: VkPipelineBindPoint = ifx pipeline.type == .GRAPHICS then .GRAPHICS else .COMPUTE;

    vkCmdBindPipeline(vk_cmd_buff, bind_point, pipeline.vk_pipeline);
    // #todo: Do we need to rebind this every time? All the pipelines share the same pipeline layout so the binding is compatible.
    bind_descriptor_buffer(vk_cmd_buff, bind_point);
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

gpu_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .COMPUTE_BIT, 2 * size_of(Gpu_Ptr), size_of(Gpu_Ptr), *data);
    vkCmdDispatch(vk_cmd_buff, dimensions[0], dimensions[1], dimensions[2]);
}

gpu_indirect_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions_gpu: Gpu_Ptr) {

}

gpu_begin_render_pass :: (cmd: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc) {
    vk_cmd_buff := get_cmd_buff(cmd);

    color_attachments: [MAX_ATTACHMENTS] VkRenderingAttachmentInfo;

    render_area: VkRect2D = .{offset = .{0, 0}};
    layer_count: u32 = 1;
    for desc.color_targets {
        view := get_texture_view(it.view);
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

    // #todo: Custom control over viewports will be required
    viewport := VkViewport.{x = 0, y = 0, width = xx render_area.extent.width, height = xx render_area.extent.height, minDepth = 0, maxDepth = 1};
    vkCmdSetViewport(vk_cmd_buff, 0, 1, *viewport);
    // #todo: custom control over scissor will be required.
    vkCmdSetScissor(vk_cmd_buff, 0, 1, *render_area);
}

gpu_end_render_pass :: (cmd: Gpu_Command_Buffer) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdEndRendering(vk_cmd_buff);
}

gpu_draw_indexed_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, index_count: u32, instance_count: u32) {
    vk_cmd_buff := get_cmd_buff(cmd);

    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, 0, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, 1 * size_of(VkDeviceAddress), size_of(VkDeviceAddress), *pixel_data);

    index_buffer, offset := get_buffer_and_offset(index_data);

    vkCmdBindIndexBuffer(vk_cmd_buff, index_buffer, offset.(VkDeviceSize), .UINT32);
    vkCmdDrawIndexed(vk_cmd_buff, index_count, instance_count, 0, 0, 0);
}


/** Queue resource for deletion when this command buffer finishes execution */
gpu_enqueue_destroy :: (queue_handle: Gpu_Queue, cmd: Gpu_Command_Buffer, gpu_ptr: Gpu_Ptr) {
    queue := get_queue(queue_handle);
    garbage_list := *garbage_allocations[queue.global_index];
    array_add(garbage_list, .{queue.timeline_value, gpu_ptr});
}

gpu_enqueue_destroy :: (queue_handle: Gpu_Queue, cmd: Gpu_Command_Buffer, texture: Gpu_Texture) {
    queue := get_queue(queue_handle);
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
    assert(cmd_buff != 0);
    index := get_cmd_buff_index(cmd_buff);
    assert(index < live_pools.count);
    pool := live_pools[index];

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
