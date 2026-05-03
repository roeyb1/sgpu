#scope_export

gpu_create_texture :: (desc: Gpu_Texture_Desc, optional_signal_texture_ready: [] Gpu_Timeline_Pair = .[], label: string = "") -> Gpu_Result, Gpu_Texture {
    create_flags: VkImageCreateFlags = 0;
    if desc.type == .CUBE || desc.type == .CUBE_ARRAY {
        create_flags |= .CUBE_COMPATIBLE_BIT;
    }

    image_create_info := VkImageCreateInfo.{
        flags = create_flags,
        format = desc.format.(VkFormat),
        extent = VkExtent3D.{desc.dimensions[0], desc.dimensions[1], desc.dimensions[2]},
        imageType = texture_type_to_vk_image_type(desc.type),
        mipLevels = desc.mip_count,
        arrayLayers = desc.layer_count,
        samples = desc.sample_count.(VkSampleCountFlagBits),
        usage = desc.usage.(VkImageUsageFlagBits),
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = num_queue_families,
        pQueueFamilyIndices = queue_family_indices.data,
        initialLayout = .UNDEFINED,
    };

    alloc_create_info := VmaAllocationCreateInfo.{
        requiredFlags = .DEVICE_LOCAL_BIT
    };

    image: VkImage;
    alloc: VmaAllocation;

    alloc_info: VmaAllocationInfo;
    vk_result := vmaCreateImage(vma, *image_create_info, *alloc_create_info, *image, *alloc, *alloc_info);
    return_if_error(vk_result, 0);

    handle := pool_add(*live_textures, .{desc = desc, vk_image = image, allocation = alloc});
    if handle == 0 {
        return .ERROR_TEXTURE_LIMIT_EXCEEDED, 0;
    }

    #if DEBUG_MARKERS then set_object_debug_name(.IMAGE, cast(u64) image, label);

    transfer_queue := gpu_get_queue(.MAIN, 0);
    result, cmd_buff := gpu_start_command_recording(transfer_queue);
    return_if_error(result, 0);

    vk_cmd_buff := get_cmd_buff(cmd_buff);

    image_barrier := VkImageMemoryBarrier2.{
        image = image,
        srcStageMask = cast(u64) VkPipelineStageFlags.TOP_OF_PIPE_BIT,
        dstStageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
        subresourceRange = .{
            baseMipLevel = 0,
            baseArrayLayer = 0,
            levelCount = desc.mip_count,
            layerCount = desc.layer_count,
            aspectMask = get_image_aspect_mask(desc.format),
        },
        oldLayout = .UNDEFINED,
        newLayout = .GENERAL,
    };

    dep_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier,
    };

    vkCmdPipelineBarrier2(vk_cmd_buff, *dep_info);

    gpu_submit(cmd_buff, signals = optional_signal_texture_ready);

    return .SUCCESS, handle;
}

gpu_free :: (texture_handle: Gpu_Texture) {
    found, texture := pool_remove(*live_textures, texture_handle);
    if !found then return;

    for texture.views {
        cleanup_texture_view(it);
    }
    // ensure we don't leak the resizable array's memory
    array_free(texture.views);

    if texture.allocation {
        vmaDestroyImage(vma, texture.vk_image, texture.allocation);
    }
}


gpu_copy_to_texture :: (dest: Gpu_Texture, src: *void, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) {
    texture := get_texture(dest);
    assert(texture != null);

    base_layer := layer_slice[0];
    copy_region := VkMemoryToImageCopy.{
        pHostPointer = src,
        memoryRowLength = 0,
        memoryImageHeight = 0,
        imageSubresource = VkImageSubresourceLayers.{
            aspectMask = get_image_aspect_mask(texture.desc.format),
            mipLevel = mip,
            baseArrayLayer = base_layer,
            layerCount = min(layer_slice[1], texture.desc.layer_count - base_layer),
        },
        imageExtent = VkExtent3D.{texture.desc.dimensions[0], texture.desc.dimensions[1], texture.desc.dimensions[2]}
    };

    copy_info := VkCopyMemoryToImageInfo.{
        dstImage = texture.vk_image,
        dstImageLayout = .GENERAL,
        regionCount = 1,
        pRegions = *copy_region,
    };
    vk_result := vkCopyMemoryToImage(vk_device, *copy_info);
    assert_vk_result(vk_result);
}

gpu_copy_from_texture :: (cmd: Gpu_Command_Buffer, dest_buffer: Gpu_Ptr, src_texture: Gpu_Texture, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) -> Gpu_Result {
    texture := get_texture(src_texture);
    if !texture then return .ERROR_INVALID_TEXTURE;

    result, dst_buffer, dst_offset := get_buffer_and_offset(dest_buffer);
    return_if_error(result);

    base_layer := layer_slice[0];
    copy_region := VkBufferImageCopy.{
        bufferOffset = dst_offset.(VkDeviceSize),
        bufferRowLength = 0,
        bufferImageHeight = 0,
        imageOffset = VkOffset3D.{},
        imageSubresource = VkImageSubresourceLayers.{
            aspectMask = get_image_aspect_mask(texture.desc.format),
            mipLevel = mip,
            baseArrayLayer = base_layer,
            layerCount = min(layer_slice[1], texture.desc.layer_count - base_layer),
        },
        imageExtent = VkExtent3D.{texture.desc.dimensions[0], texture.desc.dimensions[1], texture.desc.dimensions[2]},
    };

    vkCmdCopyImageToBuffer(get_cmd_buff(cmd), texture.vk_image, .GENERAL, dst_buffer, 1, *copy_region);
    return .SUCCESS;
}

gpu_texture_view :: (texture_handle: Gpu_Texture, desc: Gpu_View_Desc = .{}) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    if !texture then return 0;

    // if the view desc doesn't define a specific format then just use the texture native format.
    format := ifx desc.format != .UNDEFINED then desc.format else texture.desc.format;

    create_info := VkImageViewCreateInfo.{
        image = texture.vk_image,
        viewType = texture.desc.type.(VkImageViewType),
        format = format.(VkFormat),
        subresourceRange = .{
            aspectMask = get_image_aspect_mask(format),
            baseMipLevel = desc.base_mip,
            levelCount = min(desc.mip_count, texture.desc.mip_count),
            baseArrayLayer = desc.base_layer,
            layerCount = min(desc.layer_count, texture.desc.layer_count),
        },
    };

    vk_view: VkImageView;
    vk_result := vkCreateImageView(vk_device, *create_info, null, *vk_view);
    assert_vk_result(vk_result);

    handle := pool_add(*live_views, .{desc, texture_handle, vk_view});

    if handle == 0 {
        vkDestroyImageView(vk_device, vk_view, null);
        log_error("Exceeded maximum number of texture views (%)!", live_views.max);
        return 0;
    }

    array_add(*texture.views, handle,, cpu_allocator);

    if texture.desc.usage & .SAMPLED != 0 {
        write_texture_descriptor(vk_view, handle);
    }
    if texture.desc.usage & .STORAGE != 0 {
        write_rw_texture_descriptor(vk_view, handle);
    }
    return handle;
}

gpu_texture_desc :: (view_handle: Gpu_Texture_View) -> bool, Gpu_Texture_Desc {
    view := pool_get(live_views, view_handle);
    if !view {
        return false, .{};
    }
    texture := pool_get(live_textures, view.texture);
    if !texture {
        return false, .{};
    }
    return true, texture.desc;
}

gpu_create_sampler :: (desc: Gpu_Sampler_Desc, label: string = "") -> Gpu_Sampler {
    create_info := VkSamplerCreateInfo.{
        minFilter = desc.min_filter.(VkFilter),
        magFilter = desc.mag_filter.(VkFilter),
        mipmapMode = desc.mip_filter.(VkSamplerMipmapMode),
        addressModeU = desc.address_mode_u.(VkSamplerAddressMode),
        addressModeV = desc.address_mode_v.(VkSamplerAddressMode),
        addressModeW = desc.address_mode_w.(VkSamplerAddressMode),
        // MoltenVK does not support mip lod bias.
        mipLodBias = #ifx OS == .MACOS then 0. else desc.mip_lod_bias,
        anisotropyEnable = desc.enable_anisotropy.(VkBool32),
        compareEnable = (desc.compare_op != .NEVER).(VkBool32),
        compareOp = desc.compare_op.(VkCompareOp),
        minLod = desc.min_lod,
        maxLod = desc.max_lod,
        borderColor = desc.border_color.(VkBorderColor),
        unnormalizedCoordinates = desc.unnormalized_coordinates.(VkBool32)
    };

    vk_sampler: VkSampler;
    vk_result := vkCreateSampler(vk_device, *create_info, null, *vk_sampler);
    if vk_result != .SUCCESS {
        return 0;
    }

    handle := pool_add(*live_samplers, vk_sampler);
    if handle == 0 {
        vkDestroySampler(vk_device, vk_sampler, null);
        log_error("Exceeded maximum number of texture samplers (%)!", live_samplers.max);
        return 0;
    }

    write_sampler_descriptor(vk_sampler, handle);

    #if DEBUG_MARKERS then set_object_debug_name(.SAMPLER, cast(u64) vk_sampler, label);

    return handle;
}

gpu_free :: (sampler: Gpu_Sampler) {
    removed, sampler := pool_remove(*live_samplers, sampler);
    if removed {
        vkDestroySampler(vk_device, sampler, null);
    }
}

#scope_module

texture_type_to_vk_image_type :: (t: Texture_Type) -> VkImageType {
    if t == {
        case ._1D;        return ._1D;
        case ._2D;        return ._2D;
        case ._3D;        return ._3D;
        case .CUBE;       return ._2D;
        case ._1D_ARRAY;  return ._1D;
        case ._2D_ARRAY;  return ._2D;
        case .CUBE_ARRAY; return ._2D;
    }
    return ._2D;
}

Texture :: struct {
    desc: Gpu_Texture_Desc;
    vk_image: VkImage;
    allocation: VmaAllocation;

    // retain a mapping of texture to all known views of that texture
    // so they can be destroyed when the texture is destroyed.
    views: [..] Gpu_Texture_View;
}

Texture_View :: struct {
    desc: Gpu_View_Desc;
    texture: Gpu_Texture;
    vk_view: VkImageView;
}

live_textures: Pool(Gpu_Texture, Texture, max = MAX_IMAGES);
// #todo: readwrite and readonly textures both share the same index space.
// This effectively drops the usable index space by half. Need to split views into separate pools.
live_views: Pool(Gpu_Texture_View, Texture_View, max = MAX_IMAGES);
live_samplers: Pool(Gpu_Sampler, VkSampler,max = MAX_SAMPLERS);

get_image_aspect_mask :: (format: Format) -> VkImageAspectFlags {
    if format == {
        case .D16_UNORM; #through;
        case .X8_D24_UNORM_PACK32; #through;
        case .D32_SFLOAT;
            return .DEPTH_BIT;
        case .S8_UINT;
            return .STENCIL_BIT;
        case .D16_UNORM_S8_UINT; #through;
        case .D24_UNORM_S8_UINT; #through;
        case .D32_SFLOAT_S8_UINT;
            return .DEPTH_BIT | .STENCIL_BIT;
        case;
            return .COLOR_BIT;
    }
}

cleanup_texture_view :: (view_handle: Gpu_Texture_View) {
    removed, view := pool_remove(*live_views, view_handle);
    if removed {
        vkDestroyImageView(vk_device, view.vk_view, null);
    }
}

get_texture :: (texture_handle: Gpu_Texture) -> *Texture{
    texture := pool_get(live_textures, texture_handle);
    return texture;
}

get_texture_view :: (view_handle: Gpu_Texture_View) -> *Texture_View {
    view := pool_get(live_views, view_handle);
    return view;
}
