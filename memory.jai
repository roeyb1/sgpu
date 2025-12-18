Gpu_Ptr :: #type,distinct u64;

Memory_Type :: enum {
    DEFAULT;
    GPU;
    READBACK;
}

gpu_malloc :: (size: s64, memory_type: Memory_Type = .DEFAULT) -> (mapped: *void, gpu: Gpu_Ptr) {
    memory_flags: VkMemoryPropertyFlagBits;
    if #complete memory_type == {
        case .DEFAULT;
            memory_flags |= .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT;
        case .GPU;
            memory_flags |= .DEVICE_LOCAL_BIT;
        case .READBACK;
            memory_flags |= .HOST_VISIBLE_BIT | .HOST_CACHED_BIT | .HOST_COHERENT_BIT;
    }

    buffer_create_info := VkBufferCreateInfo.{
        flags = .DEVICE_ADDRESS_CAPTURE_REPLAY_BIT,
        usage = .STORAGE_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT,
        size = size.(u64),
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = all_queue_family_indices.count.(u32),
        pQueueFamilyIndices = all_queue_family_indices.data
    };

    // I don't want to expose transfer usage flags to the api so just default to always having it
    // set to SRC_BIT for cpu visible buffers and DST_BIT for gpu buffers
    if memory_type == .GPU {
        // #perf: Not sure what kind of impact having transfer_dst on the few buffers that are populated by shaders.
        buffer_create_info.usage |= .TRANSFER_DST_BIT;
    } else {
        buffer_create_info.usage |= .TRANSFER_SRC_BIT;
    }

    alloc_create_info := VmaAllocationCreateInfo.{
        flags = ifx memory_type != .GPU then .MAPPED_BIT,
        requiredFlags = memory_flags
    };


    alloc_info := VmaAllocationInfo.{};
    
    result: Alloc_Info;
    vk_result := vmaCreateBuffer(vma, *buffer_create_info, *alloc_create_info, *result.vk_buffer, *result.allocation, *alloc_info);
    assert_vk_result(vk_result);

    addr_info := VkBufferDeviceAddressInfo.{buffer = result.vk_buffer };
    result.gpu_ptr = cast(Gpu_Ptr) vkGetBufferDeviceAddress(vk_device, *addr_info);
    assert(result.gpu_ptr != 0);

    mapped := null;
    if memory_type != .GPU {
        mapped = alloc_info.pMappedData;
        table_add(*cpu_allocations, mapped, result);
    }

    table_add(*gpu_allocations, result.gpu_ptr, result);

    array_add(*gpu_memory_ranges, .{start = result.gpu_ptr, end = result.gpu_ptr + size.(Gpu_Ptr) + 1});

    return mapped, result.gpu_ptr;
}

gpu_free :: (ptr: *void) {
    removed, alloc := table_remove(*cpu_allocations, ptr);
    if removed {
        removed = table_remove(*gpu_allocations, alloc.gpu_ptr);
        assert(removed);

        remove_gpu_memory_range(alloc.gpu_ptr);

        vmaDestroyBuffer(vma, alloc.vk_buffer, alloc.allocation);
    }
}

gpu_free :: (gpu_ptr: Gpu_Ptr) {
    removed, alloc := table_remove(*gpu_allocations, gpu_ptr);
    if removed {
        remove_gpu_memory_range(alloc.gpu_ptr);

        vmaDestroyBuffer(vma, alloc.vk_buffer, alloc.allocation);
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

find_memory_range :: (ptr: Gpu_Ptr) -> Gpu_Memory_Range {
    for gpu_memory_ranges {
        if ptr >= it.start && ptr < it.end then return it;
    }
    return .{};
}

remove_gpu_memory_range :: (start_ptr: Gpu_Ptr) {
    for gpu_memory_ranges {
        if it.start == start_ptr {
            remove it;
            return;
        }
    }
}

Texture :: struct {
    desc: Gpu_Texture_Desc;
    vk_image: VkImage;
    allocation: VmaAllocation;
}

live_textures: Pool(Gpu_Texture, Texture);

#import "Hash_Table";