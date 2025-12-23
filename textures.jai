#scope_export

gpu_create_texture :: (desc: Gpu_Texture_Desc) -> Gpu_Texture {
    image_create_info := VkImageCreateInfo.{
        format = desc.format.(VkFormat),
        extent = VkExtent3D.{desc.dimensions[0], desc.dimensions[1], desc.dimensions[2]},
        imageType = desc.type.(VkImageType),
        mipLevels = desc.mip_count,
        arrayLayers = desc.layer_count,
        samples = desc.sample_count.(VkSampleCountFlagBits),
        usage = desc.usage.(VkImageUsageFlagBits),
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = all_queue_family_indices.count.(u32),
        pQueueFamilyIndices = all_queue_family_indices.data,
        initialLayout = .UNDEFINED,
    };

    alloc_create_info := VmaAllocationCreateInfo.{
        requiredFlags = .DEVICE_LOCAL_BIT
    };

    image: VkImage;
    alloc: VmaAllocation;

    alloc_info: VmaAllocationInfo;
    vk_result := vmaCreateImage(vma, *image_create_info, *alloc_create_info, *image, *alloc, *alloc_info);
    assert_vk_result(vk_result);

    handle := pool_add(*live_textures, .{desc = desc, vk_image = image, allocation = alloc});
    
    // transition the image to the GENERAL layout.
    // #todo: use the transfer queue for this?
    transfer_queue := gpu_get_queue(.MAIN, 0);
    cmd_buff := gpu_start_command_recording(transfer_queue);
    vk_cmd_buff := get_cmd_buff(cmd_buff);

    // transition the image to be used in shaders.
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

    gpu_submit(transfer_queue, cmd_buff);

    return handle;
}

gpu_free :: (texture_handle: Gpu_Texture) {
    found, texture := pool_remove(*live_textures, texture_handle);
    assert(found);

    for texture.views {
        cleanup_texture_view(it);
    }

    if texture.allocation {
        vmaDestroyImage(vma, texture.vk_image, texture.allocation);
    }
}

gpu_texture_view :: (texture_handle: Gpu_Texture, desc: Gpu_View_Desc = .{}) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    assert(texture != null);

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
    
    // #todo: support array views.

    vk_view: VkImageView;
    vk_result := vkCreateImageView(vk_device, *create_info, null, *vk_view);
    assert_vk_result(vk_result);

    handle := pool_add(*live_views, .{desc, texture_handle, vk_view});

    array_add(*texture.views, handle);

    write_texture_descriptor(vk_view, handle);
    return handle;
}

gpu_texture_desc :: (view_hande: Gpu_Texture_View) -> bool, Gpu_Texture_Desc {
    view := pool_get(*live_views, view_hande);
    if !view {
        return false, .{};
    }
    texture := pool_get(*live_textures, view.texture);
    if !texture {
        return false, .{};
    }
    return true, texture.desc;
}

#scope_module

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

live_textures: Pool(Gpu_Texture, Texture);
live_views: Pool(Gpu_Texture_View, Texture_View);

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
    assert(removed);

    vkDestroyImageView(vk_device, view.vk_view, null);
}

get_texture :: (texture_handle: Gpu_Texture) -> *Texture{
    texture := pool_get(live_textures, texture_handle);
    assert(texture != null);
    return texture;
}

get_texture_view :: (view_handle: Gpu_Texture_View) -> *Texture_View {
    view := pool_get(live_views, view_handle);
    assert(view != null);
    return view;
}