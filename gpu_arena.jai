#scope_export

Gpu_Arena :: struct {
    cpu: *void;
    gpu: Gpu_Ptr;
    size: s64;

    head: s64;
}

gpu_make_arena :: (size: s64) -> Gpu_Arena {
    cpu, gpu := gpu_malloc(size);

    return .{cpu = cpu, gpu = gpu, size = size};
}

gpu_arena_alloc :: (using arena: *Gpu_Arena, $type: Type, min_alignment: s64 = 16) -> *type, Gpu_Ptr {
    result_cpu, result_gpu := gpu_arena_alloc(arena, size_of(type), min_alignment);
    return result_cpu.(*type), result_gpu;
}

gpu_arena_array_alloc :: (using arena: *Gpu_Arena, $type: Type, count: s64, min_alignment: s64 = 16) -> [] type, Gpu_Ptr {
    result_cpu, result_gpu := gpu_arena_alloc(arena, size_of(type) * count, min_alignment);
    result: [] type;
    result.data = result_cpu;
    result.count = count;
    return result, result_gpu;
}

gpu_arena_alloc :: (using arena: *Gpu_Arena, alloc_size: s64, min_alignment: s64 = 16) -> *void, Gpu_Ptr {
    alignment := calculate_alignment(min_alignment);
    aligned_size := align_forward(alloc_size, alignment);
    if head + aligned_size > size {
        return null, 0;
    }

    result_cpu := arena.cpu + arena.head;
    result_gpu := arena.gpu + arena.head.(Gpu_Ptr);
    arena.head += aligned_size;
    return result_cpu, result_gpu;
}

gpu_arena_head :: (arena: *Gpu_Arena) -> Gpu_Ptr {
    return arena.gpu + arena.head.(Gpu_Ptr);
}

gpu_reset_arena :: (arena: *Gpu_Arena) {
    arena.head = 0;
}

gpu_free_arena :: (arena: Gpu_Arena) {
    gpu_free(arena.cpu);
}

#scope_module

calculate_alignment :: (requested_alignment: s64) -> s64 {
    return max(vk_physical_device_properties.properties.limits.minStorageBufferOffsetAlignment.(s64), requested_alignment);
}
