MAX_TIMESTAMP_QUERIES :: 64;

Gpu_Timestamp :: struct {
    pool_index: u32;   // which frame-in-flight pool this belongs to
    query_index: u32;  // index within that pool
}

gpu_init_timestamps :: (swapchain_image_count: s64) {
    assert(timestamp_pools.count == 0 && swapchain_image_count > 0);
    array_resize(*timestamp_pools, swapchain_image_count);
    for * timestamp_pools {
        create_info := VkQueryPoolCreateInfo.{
            queryType  = .TIMESTAMP,
            queryCount = MAX_TIMESTAMP_QUERIES,
        };

        vk_result := vkCreateQueryPool(vk_device, *create_info, null, *it.vk_pool);
        assert(vk_result == .SUCCESS);
    }
}

gpu_destroy_timestamps :: () {
    for timestamp_pools {
        if it.vk_pool vkDestroyQueryPool(vk_device, it.vk_pool, null);
    }
    array_reset(*timestamp_pools);
}

gpu_cmd_timestamp_write :: (cmd: Gpu_Command_Buffer, stage: Stage) -> Gpu_Timestamp {
    pool_index := cast(u32)(cpu_frame_timeline % timestamp_pools.count.(u64));
    pool := *timestamp_pools[pool_index];

    query_index := pool.next_query;
    assert(query_index < MAX_TIMESTAMP_QUERIES, "Exceeded MAX_TIMESTAMP_QUERIES (%) per frame", MAX_TIMESTAMP_QUERIES);
    pool.next_query += 1;

    vkCmdWriteTimestamp(get_cmd_buff(cmd), cast(VkPipelineStageFlagBits) stage, pool.vk_pool, query_index);

    return .{ pool_index = pool_index, query_index = query_index };
}

gpu_timestamp_duration_ms :: (begin: Gpu_Timestamp, end: Gpu_Timestamp) -> (ready: bool, ms: float64) {
    if begin.pool_index != end.pool_index then return false, 0.;

    timestamps: [2] u64;
    queries: [2] u32 = .[begin.query_index, end.query_index];

    vk_result := vkGetQueryPoolResults(
        vk_device,
        timestamp_pools[begin.pool_index].vk_pool,
        queries[0], 1,
        size_of(u64), *timestamps[0], size_of(u64),
        ._64_BIT,
    );

    if vk_result != .SUCCESS then return false, 0;

    vk_result = vkGetQueryPoolResults(
        vk_device,
        timestamp_pools[end.pool_index].vk_pool,
        queries[1], 1,
        size_of(u64), *timestamps[1], size_of(u64),
        ._64_BIT,
    );
    if vk_result != .SUCCESS then return false, 0;

    delta := timestamps[1] - timestamps[0];
    period_ns := cast(float64) vk_physical_device_properties.properties.limits.timestampPeriod;
    ms := cast(float64) delta * period_ns / 1_000_000.0;
    return true, ms;
}

#scope_module

Timestamp_Pool :: struct {
    vk_pool: VkQueryPool;
    next_query: u32;
}

timestamp_pools: [..] Timestamp_Pool;

timestamps_reset :: (cmd: Gpu_Command_Buffer) {
    pool := *timestamp_pools[cpu_frame_timeline % timestamp_pools.count.(u64)];
    pool.next_query = 0;
    vkCmdResetQueryPool(get_cmd_buff(cmd), pool.vk_pool, 0, MAX_TIMESTAMP_QUERIES);
}
