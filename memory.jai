Gpu_Ptr :: #type,distinct u64;

Memory_Type :: enum {
    DEFAULT;
    GPU;
    READBACK;
}

gpu_malloc :: ($type: Type, memory_type: Memory_Type = .DEFAULT) -> (mapped: *type, gpu: Gpu_Ptr) {
    cpu_ptr, gpu_ptr := gpu_malloc(size_of(type), memory_type);
    return cpu_ptr.(*type), gpu_ptr;
}

gpu_malloc :: (size: s64, memory_type: Memory_Type = .DEFAULT) -> (mapped: *void, gpu: Gpu_Ptr) {
    memory_flags: VkMemoryPropertyFlagBits;
    memory_usage_flags: VmaMemoryUsage;
    if #complete memory_type == {
        case .DEFAULT;
            memory_flags |= .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT;
            memory_usage_flags |= .CPU_TO_GPU;
        case .GPU;
            memory_flags |= .DEVICE_LOCAL_BIT;
            memory_usage_flags |= .GPU_ONLY;
        case .READBACK;
            memory_flags |= .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT | .HOST_CACHED_BIT;
            memory_usage_flags |= .GPU_TO_CPU;
    }

    buffer_create_info := VkBufferCreateInfo.{
        // To avoid exposing buffer usage flags to the API, we allow all buffers to be used for any type of operations
        usage = .STORAGE_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT | .TRANSFER_DST_BIT | .TRANSFER_SRC_BIT,
        size = size.(u64),
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = num_queue_families,
        pQueueFamilyIndices = queue_family_indices.data
    };

    alloc_create_info := VmaAllocationCreateInfo.{
        flags = ifx memory_type != .GPU then .MAPPED_BIT,
        requiredFlags = memory_flags,
        usage = memory_usage_flags,
    };


    alloc_info := VmaAllocationInfo.{};

    result: Alloc_Info;
    vk_result := vmaCreateBuffer(vma, *buffer_create_info, *alloc_create_info, *result.vk_buffer, *result.allocation, *alloc_info);
    if vk_result != .SUCCESS {
        return null, 0;
    }

    addr_info := VkBufferDeviceAddressInfo.{buffer = result.vk_buffer };
    result.gpu_ptr = cast(Gpu_Ptr) vkGetBufferDeviceAddress(vk_device, *addr_info);
    if result.gpu_ptr == 0 {
        vmaDestroyBuffer(vma, result.vk_buffer, result.allocation);
        return null, 0;
    }

    mapped := null;
    if memory_type != .GPU {
        mapped = alloc_info.pMappedData;
        table_add(*cpu_allocations, mapped, result);
    }

    table_add(*gpu_allocations, result.gpu_ptr, result);

    array_add(*gpu_memory_ranges, .{start = result.gpu_ptr, end = result.gpu_ptr + size.(Gpu_Ptr)});

    return mapped, result.gpu_ptr;
}

gpu_free :: (ptr: *void) {
    removed, alloc := table_remove(*cpu_allocations, ptr);
    if removed {
        vmaDestroyBuffer(vma, alloc.vk_buffer, alloc.allocation);

        removed = table_remove(*gpu_allocations, alloc.gpu_ptr);
        debug_assert(removed);

        removed = remove_gpu_memory_range(alloc.gpu_ptr);
        debug_assert(removed);
    }
}

gpu_free :: (gpu_ptr: Gpu_Ptr) {
    removed, alloc := table_remove(*gpu_allocations, gpu_ptr);
    if removed {
        vmaDestroyBuffer(vma, alloc.vk_buffer, alloc.allocation);

        removed = remove_gpu_memory_range(alloc.gpu_ptr);
        debug_assert(removed);
    }
}

gpu_host_to_device_ptr :: (host: *void) -> Gpu_Ptr {
    found, alloc := table_find(*allocations, host);
    if found {
        return alloc.gpu_ptr;
    }
    return 0;
}

#scope_module

Alloc_Info :: struct {
    allocation: VmaAllocation;
    gpu_ptr: Gpu_Ptr;
    type: Memory_Type;

    vk_buffer: VkBuffer;
}

/** Maps the mapped cpu accessible pointer to a given gpu memory allocation */
cpu_allocations: Table(*void, Alloc_Info);
/** Maps the gpu accessible pointer to a given gpu memory allocation */
gpu_allocations: Table(Gpu_Ptr, Alloc_Info);

Gpu_Memory_Range :: struct {
    start: Gpu_Ptr;
    end: Gpu_Ptr;
}

// #perf: store this in some sort of sorted btree container so it ordered and is faster to iterate?
// I expect many gpu memory ranges to be live at once so binary search will *likely* be faster.
// Needs profiling.
gpu_memory_ranges: [..] Gpu_Memory_Range;

find_memory_range :: (ptr: Gpu_Ptr) -> Gpu_Result, Gpu_Memory_Range {
    for gpu_memory_ranges {
        if ptr >= it.start && ptr < it.end then return .SUCCESS, it;
    }
    return .ERROR_UNKNOWN_GPU_POINTER, .{};
}

remove_gpu_memory_range :: (start_ptr: Gpu_Ptr) -> bool {
    for gpu_memory_ranges {
        if it.start == start_ptr {
            remove it;
            return true;
        }
    }
    return false;
}

get_buffer :: (gpu_ptr: Gpu_Ptr) -> VkBuffer {
    found, alloc := table_find(*gpu_allocations, gpu_ptr);
    if !found {
        return VK_NULL_HANDLE;
    }
    return alloc.vk_buffer;
}

get_buffer_and_offset :: (gpu_ptr: Gpu_Ptr) -> Gpu_Result, VkBuffer, s64 {
    result, range := find_memory_range(gpu_ptr);
    if result != .SUCCESS then return result, VK_NULL_HANDLE, 0;
    debug_assert(range.start != 0);

    vk_buffer := get_buffer(range.start);
    debug_assert(vk_buffer != VK_NULL_HANDLE);
    return .SUCCESS, vk_buffer, (gpu_ptr - range.start).(s64);
}

#import "Hash_Table";
