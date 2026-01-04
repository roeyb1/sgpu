#scope_module

TEXTURE_BINDING :: 0;
RW_TEXTURE_BINDING :: 1;
SAMPLER_BINDING :: 2;

initialize_descriptors :: () -> Gpu_Result {
    result := create_descriptor_set_layout();
    return_if_error(result);

    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        result = create_descriptor_buffer();
        return_if_error(result);
    } else {
        result = create_descriptor_set();
        return_if_error(result);
    }

    return .SUCCESS;
}

bind_descriptors :: (cmd_buff: VkCommandBuffer, bind_point: VkPipelineBindPoint) {
    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        binding_info := VkDescriptorBufferBindingInfoEXT.{
            address = bindless_buffer.gpu_ptr,
            usage = .RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
        };
        vkCmdBindDescriptorBuffersEXT(cmd_buff, 1, *binding_info);

        index: u32 = 0;
        offset: VkDeviceSize = 0;
        vkCmdSetDescriptorBufferOffsetsEXT(cmd_buff, bind_point, vk_pipeline_layout, 0, 1, *index, *offset);
    } else {
        vkCmdBindDescriptorSets(cmd_buff, bind_point, vk_pipeline_layout, 0, 1, *bindless_set, 0, null);
    }
}

write_texture_descriptor :: (vk_view: VkImageView, index: Gpu_Texture_View) {
    image_info := VkDescriptorImageInfo.{
        imageView = vk_view,
        imageLayout = .GENERAL,
    };

    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        binding_offset: VkDeviceSize;
        vkGetDescriptorSetLayoutBindingOffsetEXT(vk_device, bindless_set_layout, TEXTURE_BINDING, *binding_offset);

        binding := bindless_buffer.mapped + binding_offset;

        image_descriptor_size := descriptor_properties.sampledImageDescriptorSize;
        element_ptr := binding + (index.(u64) * image_descriptor_size);

        get_info := VkDescriptorGetInfoEXT.{
            type = .SAMPLED_IMAGE,
            data.pSampledImage = *image_info,
        };

        vkGetDescriptorEXT(vk_device, *get_info, image_descriptor_size, element_ptr);
    } else {
        write := VkWriteDescriptorSet.{
            dstSet = bindless_set,
            dstBinding = TEXTURE_BINDING,
            dstArrayElement = index.(u32),
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = *image_info,
        };

        vkUpdateDescriptorSets(vk_device, 1, *write, 0, null);
    }
}

write_rw_texture_descriptor :: (vk_view: VkImageView, index: Gpu_Texture_View) {
    image_info := VkDescriptorImageInfo.{
        imageView = vk_view,
        imageLayout = .GENERAL,
    };

    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        binding_offset: VkDeviceSize;
        vkGetDescriptorSetLayoutBindingOffsetEXT(vk_device, bindless_set_layout, RW_TEXTURE_BINDING, *binding_offset);

        binding := bindless_buffer.mapped + binding_offset;

        image_descriptor_size := descriptor_properties.storageImageDescriptorSize;
        element_ptr := binding + (index.(u64) * image_descriptor_size);

        get_info := VkDescriptorGetInfoEXT.{
            type = .STORAGE_IMAGE,
            data.pSampledImage = *image_info,
        };

        vkGetDescriptorEXT(vk_device, *get_info, image_descriptor_size, element_ptr);
    } else {
        write := VkWriteDescriptorSet.{
            dstSet = bindless_set,
            dstBinding = RW_TEXTURE_BINDING,
            dstArrayElement = index.(u32),
            descriptorCount = 1,
            descriptorType = .STORAGE_IMAGE,
            pImageInfo = *image_info,
        };

        vkUpdateDescriptorSets(vk_device, 1, *write, 0, null);
    }
}

write_sampler_descriptor :: (vk_sampler: VkSampler, index: Gpu_Sampler) {
    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        binding_offset: VkDeviceSize;
        vkGetDescriptorSetLayoutBindingOffsetEXT(vk_device, bindless_set_layout, SAMPLER_BINDING, *binding_offset);

        binding := bindless_buffer.mapped + binding_offset;

        sampler_descriptor_size := descriptor_properties.samplerDescriptorSize;
        element_ptr := binding + (index.(u64) * sampler_descriptor_size);

        get_info := VkDescriptorGetInfoEXT.{
            type = .SAMPLER,
            data.pSampler = *vk_sampler,
        };

        vkGetDescriptorEXT(vk_device, *get_info, sampler_descriptor_size, element_ptr);
    } else {
        image_info := VkDescriptorImageInfo.{
            sampler = vk_sampler,
            imageLayout = .GENERAL,
        };

        write := VkWriteDescriptorSet.{
            dstSet = bindless_set,
            dstBinding = SAMPLER_BINDING,
            dstArrayElement = index.(u32),
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = *image_info,
        };

        vkUpdateDescriptorSets(vk_device, 1, *write, 0, null);
    }
}

destroy_descriptors :: () {
    if is_optional_ext_supported(.DESCRIPTOR_BUFFER) {
        vmaDestroyBuffer(vma, bindless_buffer.vk_buffer, bindless_buffer.allocation);
    } else {
        vkFreeDescriptorSets(vk_device, bindless_pool, 1, *bindless_set);
        vkDestroyDescriptorPool(vk_device, bindless_pool, null);
    }
}

bindless_set_layout: VkDescriptorSetLayout;

vkGetDescriptorSetLayoutSizeEXT: PFN_vkGetDescriptorSetLayoutSizeEXT;
vkGetDescriptorSetLayoutBindingOffsetEXT: PFN_vkGetDescriptorSetLayoutBindingOffsetEXT;
vkGetDescriptorEXT: PFN_vkGetDescriptorEXT;
vkCmdBindDescriptorBuffersEXT: PFN_vkCmdBindDescriptorBuffersEXT;
vkCmdSetDescriptorBufferOffsetsEXT: PFN_vkCmdSetDescriptorBufferOffsetsEXT;

#scope_file

create_descriptor_set_layout :: () -> Gpu_Result {
    properties: VkPhysicalDeviceProperties2;
    properties.pNext = *descriptor_properties;
    vkGetPhysicalDeviceProperties2(vk_physical_device, *properties);

    num_sampled_images = min(properties.properties.limits.maxPerStageDescriptorSampledImages, MAX_IMAGES);
    num_storage_images = min(properties.properties.limits.maxPerStageDescriptorStorageImages, MAX_IMAGES);
    num_samplers = min(properties.properties.limits.maxPerStageDescriptorSamplers, MAX_SAMPLERS);

    bindings := VkDescriptorSetLayoutBinding.[
        .{
            binding = TEXTURE_BINDING,
            descriptorType = .SAMPLED_IMAGE,
            descriptorCount = num_sampled_images,
            stageFlags = .ALL,
        },
        .{
            binding = RW_TEXTURE_BINDING,
            descriptorType = .STORAGE_IMAGE,
            descriptorCount = num_storage_images,
            stageFlags = .ALL,
        },
        .{
            binding = SAMPLER_BINDING,
            descriptorType = .SAMPLER,
            descriptorCount = num_samplers,
            stageFlags = .ALL,
        }
    ];

    use_descriptor_buffer := is_optional_ext_supported(.DESCRIPTOR_BUFFER);

    binding_flags := VkDescriptorBindingFlags.[
        .PARTIALLY_BOUND_BIT | ifx !use_descriptor_buffer then .UPDATE_AFTER_BIND_BIT else (0).(VkDescriptorBindingFlags),
        .PARTIALLY_BOUND_BIT | ifx !use_descriptor_buffer then .UPDATE_AFTER_BIND_BIT else (0).(VkDescriptorBindingFlags),
        .PARTIALLY_BOUND_BIT | ifx !use_descriptor_buffer then .UPDATE_AFTER_BIND_BIT else (0).(VkDescriptorBindingFlags),
    ];
    debug_assert(binding_flags.count == bindings.count);

    binding_flags_info := VkDescriptorSetLayoutBindingFlagsCreateInfo.{
        bindingCount = binding_flags.count.(u32),
        pBindingFlags = binding_flags.data,
    };

    create_info := VkDescriptorSetLayoutCreateInfo.{
        pNext = *binding_flags_info,
        flags = ifx use_descriptor_buffer then .DESCRIPTOR_BUFFER_BIT_EXT else .UPDATE_AFTER_BIND_POOL_BIT,
        bindingCount = bindings.count.(u32),
        pBindings = bindings.data
    };


    vk_result := vkCreateDescriptorSetLayout(vk_device, *create_info, null, *bindless_set_layout);
    return_if_error(vk_result);

    return .SUCCESS;
}

create_descriptor_buffer :: () -> Gpu_Result {
    descriptor_buffer_size: VkDeviceSize;
    // calculate size + offset.
    {
        layout_size: VkDeviceSize;
        vkGetDescriptorSetLayoutSizeEXT(vk_device, bindless_set_layout, *layout_size);

        alignment := descriptor_properties.descriptorBufferOffsetAlignment;

        descriptor_buffer_size = align_forward(layout_size, alignment);
    }

    buffer_create_info := VkBufferCreateInfo.{
        usage = .RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | .SHADER_DEVICE_ADDRESS_BIT,
        size = descriptor_buffer_size.(u64),
    };
    alloc_create_info := VmaAllocationCreateInfo.{
        flags = .MAPPED_BIT,
        usage = .CPU_TO_GPU,
    };

    alloc_info: VmaAllocationInfo;
    vk_result := vmaCreateBuffer(vma, *buffer_create_info, *alloc_create_info, *bindless_buffer.vk_buffer, *bindless_buffer.allocation, *alloc_info);
    if vk_result != .SUCCESS {
        vkDestroyDescriptorSetLayout(vk_device, bindless_set_layout, null);
        return_if_error(vk_result);
    }

    addr_info := VkBufferDeviceAddressInfo.{buffer = bindless_buffer.vk_buffer };
    bindless_buffer.gpu_ptr = vkGetBufferDeviceAddress(vk_device, *addr_info);
    bindless_buffer.mapped = alloc_info.pMappedData;

    if bindless_buffer.gpu_ptr == 0 {
        vmaDestroyBuffer(vma, bindless_buffer.vk_buffer, bindless_buffer.allocation);
        vkDestroyDescriptorSetLayout(vk_device, bindless_set_layout, null);
        return .FATAL_ERROR_UNKNOWN;
    }

    return .SUCCESS;
}

create_descriptor_set :: () -> Gpu_Result {
    pool_sizes := VkDescriptorPoolSize.[
        .{
            type = .SAMPLED_IMAGE,
            descriptorCount = num_sampled_images,
        },
        .{
            type = .STORAGE_IMAGE,
            descriptorCount = num_storage_images,
        },
        .{
            type = .SAMPLER,
            descriptorCount = num_samplers,
        },
    ];

    create_info := VkDescriptorPoolCreateInfo.{
        flags = .FREE_DESCRIPTOR_SET_BIT | .UPDATE_AFTER_BIND_BIT,
        maxSets = 1,
        poolSizeCount = pool_sizes.count.(u32),
        pPoolSizes = pool_sizes.data,
    };

    vk_result := vkCreateDescriptorPool(vk_device, *create_info, null, *bindless_pool);
    return_if_error(vk_result);


    alloc_info := VkDescriptorSetAllocateInfo.{
        descriptorPool = bindless_pool,
        descriptorSetCount = 1,
        pSetLayouts = *bindless_set_layout,
    };

    vk_result = vkAllocateDescriptorSets(vk_device, *alloc_info, *bindless_set);
    return_if_error(vk_result);

    return .SUCCESS;
}

descriptor_properties: VkPhysicalDeviceDescriptorBufferPropertiesEXT;
num_sampled_images: u32;
num_storage_images: u32;
num_samplers: u32;

bindless_buffer: struct {
    vk_buffer: VkBuffer;
    allocation: VmaAllocation;
    gpu_ptr: VkDeviceAddress;
    mapped: *void;
};

// only used when descriptor buffer extension is not present.
bindless_pool: VkDescriptorPool;
bindless_set: VkDescriptorSet;

align_forward :: (size: VkDeviceSize, align: VkDeviceSize) -> VkDeviceSize {
    return (size + align - 1) & ~(align - 1);
}
