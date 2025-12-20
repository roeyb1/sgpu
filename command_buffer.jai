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

    // #todo: factor out
    queue := get_queue(queue_handle);

    family_index := queue.type;

    arena := *cmd_pools[family_index];

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

    // find an empty slot in the live pools list
    found, index := array_find(live_pools, null);
    // the list is preallocated to the maximum number of possible live command lists so this should never fail.
    assert(found);

    live_pools[index] = pool;

    cmd_buff_handle := cast(Gpu_Command_Buffer) (index + 1);

    begin_info := VkCommandBufferBeginInfo.{
        flags = .ONE_TIME_SUBMIT_BIT
    };
    vkBeginCommandBuffer(pool.vk_cmd_buff, *begin_info);

    return cmd_buff_handle;
}

gpu_submit :: (queue_handle: Gpu_Queue, buffer: Gpu_Command_Buffer, signal: Gpu_Semaphore = 0, signal_value: u64 = 0) {
    assert(buffer != 0);
    index := (buffer - 1);
    assert(index < live_pools.count);
    pool := live_pools[index];

    vkEndCommandBuffer(pool.vk_cmd_buff);

    queue := get_queue(queue_handle);

    queue_timeline_value := atomic_add(*queue.timeline_value, 1) + 1; // atomic_add returns the previous value.

    signal_values := u64.[queue_timeline_value, 0];
    signal_semaphores := VkSemaphore.[queue.timeline, VK_NULL_HANDLE];
    signal_count: u32 = 1;

    if signal != 0 {
        vk_semaphore := get_semaphore(signal);
        signal_semaphores[1] = vk_semaphore;
        signal_values[1] = signal_value;
        signal_count += 1;
    }

    timeline_info := VkTimelineSemaphoreSubmitInfo.{
        signalSemaphoreValueCount = signal_count,
        pSignalSemaphoreValues = signal_values.data,
    };

    cmd_buffers := VkCommandBuffer.[pool.vk_cmd_buff];
    submit_info := VkSubmitInfo.{
        pNext = *timeline_info,
        commandBufferCount = cmd_buffers.count.(u32),
        pCommandBuffers = cmd_buffers.data,
        signalSemaphoreCount = signal_count,
        pSignalSemaphores = signal_semaphores.data,
    };
    vkQueueSubmit(queue.vk_queue, 1, *submit_info, VK_NULL_HANDLE);

    live_pools[index] = null;
    array_add(*garbage_pools[queue.type], .{queue_timeline_value, pool});
}

gpu_memcpy :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, num_bytes: s64) {
    cmd_buff := get_cmd_buff(cmd);

    dest_alloc_range := find_memory_range(dest);
    src_alloc_range := find_memory_range(src);

    assert(dest_alloc_range.start != 0);
    assert(src_alloc_range.start != 0);

    // ensure the copy region is valid for both memory ranges.
    assert(dest + num_bytes.(Gpu_Ptr) < dest_alloc_range.end);
    assert(src + num_bytes.(Gpu_Ptr) < dest_alloc_range.end);

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

gpu_copy_to_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, texture: Gpu_Texture) {

}

gpu_copy_from_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, texture: Gpu_Texture) {

}


gpu_barrier :: (cmd: Gpu_Command_Buffer, before: Stage, after: Stage) {

}

gpu_signal_after :: (cmd: Gpu_Command_Buffer, before: Stage, ptr: Gpu_Ptr, value: u64, signal: Signal) {
    
}

gpu_wait_before :: (cmd: Gpu_Command_Buffer, after: Stage, ptr: Gpu_Ptr, value: u64, op: Op, signal: Signal) {
    
}


gpu_set_pipeline :: (cmd: Gpu_Command_Buffer, pipeline_handle: Gpu_Pipeline) {
    vk_cmd_buff := get_cmd_buff(cmd);
    pipeline := pool_get(live_pipelines, pipeline_handle);

    bind_point: VkPipelineBindPoint = ifx pipeline.type == .GRAPHICS then .GRAPHICS else .COMPUTE;

    vkCmdBindPipeline(vk_cmd_buff, bind_point, pipeline.vk_pipeline);
    // #todo: Do we need to rebind this every time? All the pipelines share the same pipeline layout so the binding is compatible.
    bind_descriptor_buffer(vk_cmd_buff);
}

gpu_set_depth_stencil_state :: (cmd: Gpu_Command_Buffer, state: Gpu_Depth_Stencil_State) {

}

gpu_set_blend_state :: (cmd: Gpu_Command_Buffer, state: Gpu_Blend_State) {

}

gpu_dispatch :: (cmd: Gpu_Command_Buffer, dimensions: [3] u32) {

}

gpu_indirect_dispatch :: (cmd: Gpu_Command_Buffer, dimensions_gpu: Gpu_Ptr) {

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
            clearValue.color._float32[0] = xx it.clear_color[0],
            clearValue.color._float32[1] = xx it.clear_color[1],
            clearValue.color._float32[2] = xx it.clear_color[2],
            clearValue.color._float32[3] = xx it.clear_color[3],
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
            clearValue.depthStencil.depth = desc.depth_target.clear_value,
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
            clearValue.depthStencil.stencil = desc.stencil_target.clear_color[0],
        };
        render_info.pStencilAttachment = *stencil_attachment;
    }

    render_info.renderArea = render_area;

    vkCmdBeginRendering(vk_cmd_buff, *render_info);
}

gpu_end_render_pass :: (cmd: Gpu_Command_Buffer) {
    vk_cmd_buff := get_cmd_buff(cmd);
    vkCmdEndRendering(vk_cmd_buff);
}

gpu_draw_indexed_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, index_count: u32, instance_count: u32) {
    vk_cmd_buff := get_cmd_buff(cmd);

    // hard code this for now until dynamic viewport/scissor is set up.
    render_area: VkRect2D = .{offset = .{0, 0}, extent = .{1024, 1024}};
    // for ease of use, always set the viewport to the full viewport.
    // #todo: Custom control over viewports will be required
    viewport := VkViewport.{x = 0, y = 0, width = xx render_area.extent.width, height = xx render_area.extent.height, minDepth = 0, maxDepth = 1};
    vkCmdSetViewport(vk_cmd_buff, 0, 1, *viewport);
    // #todo: custom control over scissor will be required.
    vkCmdSetScissor(vk_cmd_buff, 0, 1, *render_area);

    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .VERTEX_BIT, 0, size_of(VkDeviceAddress), *vertex_data);
    vkCmdPushConstants(vk_cmd_buff, vk_pipeline_layout, .FRAGMENT_BIT, 1 * size_of(VkDeviceAddress), size_of(VkDeviceAddress), *pixel_data);

    index_buffer, offset := get_buffer_and_offset(index_data);

    vkCmdBindIndexBuffer(vk_cmd_buff, index_buffer, offset.(VkDeviceSize), .UINT32);
    vkCmdDrawIndexed(vk_cmd_buff, index_count, instance_count, 0, 0, 0);
}


#scope_module

MAX_COMMAND_POOLS :: 128;

Command_Pool :: struct {
    vk_cmd_pool: VkCommandPool;
    vk_cmd_buff: VkCommandBuffer;
}

Command_Pool_Arena :: struct {
    // bucket array is used here for pointer stability and to ensure stability of all elements after removal.
    // this could just be a xar + free list.
    all_pools: Bucket_Array(Command_Pool, 32);
    available_pools: [..] *Command_Pool;
}

cmd_pools: [NUM_QUEUE_FAMILIES] Command_Pool_Arena;

Garbage_Command_Pool :: struct {
    submit_timeline_value: u64;
    pool: *Command_Pool;
}

live_pools: [MAX_COMMAND_POOLS * NUM_QUEUE_FAMILIES] *Command_Pool;
// #TODO: fixed size allocation but can resizeable count within that buffer.
garbage_pools: [NUM_QUEUE_FAMILIES] [..] Garbage_Command_Pool;

reclaim_completed_command_pools :: () {
    for * arena, queue_index : cmd_pools {
        queue := *queues[queue_index];
        current_timeline_value: u64;
        vk_result := vkGetSemaphoreCounterValue(vk_device, queue.timeline, *current_timeline_value);
        assert_vk_result(vk_result);

        for garbage_pools[queue_index] {
            if it.submit_timeline_value <= current_timeline_value {
                vk_result = vkResetCommandPool(vk_device, it.pool.vk_cmd_pool, 0);
                assert_vk_result(vk_result);
                
                array_add(*arena.available_pools, it.pool);
                remove it;
            }
        }
    }
}

get_cmd_buff :: (cmd_buff_handle: Gpu_Command_Buffer) -> VkCommandBuffer {
    cmd_buff_index := (cmd_buff_handle - 1);
    assert(cmd_buff_handle >= 0 && cmd_buff_handle < live_pools.count);

    return live_pools[cmd_buff_index].vk_cmd_buff;
}