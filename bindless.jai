#scope_module

TEXTURE_BINDING :: 0;
RW_TEXTURE_BINDING :: 1;
SAMPLER_BINDING :: 2;

create_descriptor_buffer :: () -> bool {
    properties: VkPhysicalDeviceProperties2;
    properties.pNext = *descriptor_properties;
    vkGetPhysicalDeviceProperties2(vk_physical_device, *properties);

    num_sampled_images := min(properties.properties.limits.maxDescriptorSetSampledImages, MAX_IMAGES);
    num_storage_images := min(properties.properties.limits.maxDescriptorSetStorageImages, MAX_IMAGES);
    num_samplers := min(properties.properties.limits.maxDescriptorSetSamplers, MAX_SAMPLERS);

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

    create_info := VkDescriptorSetLayoutCreateInfo.{
        flags = .DESCRIPTOR_BUFFER_BIT_EXT,
        bindingCount = bindings.count.(u32),
        pBindings = bindings.data
    };


    vk_result := vkCreateDescriptorSetLayout(vk_device, *create_info, null, *bindless_set_layout);
    if vk_result != .SUCCESS {
        return false;
    }

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
    vk_result = vmaCreateBuffer(vma, *buffer_create_info, *alloc_create_info, *bindless_buffer.vk_buffer, *bindless_buffer.allocation, *alloc_info);
    if vk_result != .SUCCESS {
        vkDestroyDescriptorSetLayout(vk_device, bindless_set_layout, null);
        return false;
    }

    addr_info := VkBufferDeviceAddressInfo.{buffer = bindless_buffer.vk_buffer };
    bindless_buffer.gpu_ptr = vkGetBufferDeviceAddress(vk_device, *addr_info);
    bindless_buffer.mapped = alloc_info.pMappedData;

    if bindless_buffer.gpu_ptr == 0 {
        vmaDestroyBuffer(vma, bindless_buffer.vk_buffer, bindless_buffer.allocation);
        vkDestroyDescriptorSetLayout(vk_device, bindless_set_layout, null);
        return false;
    }

    return true;
}

bind_descriptor_buffer :: (cmd_buff: VkCommandBuffer, bind_point: VkPipelineBindPoint) {
    binding_info := VkDescriptorBufferBindingInfoEXT.{
        address = bindless_buffer.gpu_ptr,
        usage = .RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT,
    };
    vkCmdBindDescriptorBuffersEXT(cmd_buff, 1, *binding_info);

    index: u32 = 0;
    offset: VkDeviceSize = 0;
    vkCmdSetDescriptorBufferOffsetsEXT(cmd_buff, bind_point, vk_pipeline_layout, 0, 1, *index, *offset);
}

write_texture_descriptor :: (vk_view: VkImageView, index: Gpu_Texture_View) {
    binding_offset: VkDeviceSize;
    vkGetDescriptorSetLayoutBindingOffsetEXT(vk_device, bindless_set_layout, TEXTURE_BINDING, *binding_offset);

    binding := bindless_buffer.mapped + binding_offset;

    image_descriptor_size := descriptor_properties.sampledImageDescriptorSize;
    element_ptr := binding + (index.(u64) * image_descriptor_size);

    image_info := VkDescriptorImageInfo.{
        imageView = vk_view,
        imageLayout = .GENERAL,
    };

    get_info := VkDescriptorGetInfoEXT.{
        type = .SAMPLED_IMAGE,
        data.pSampledImage = *image_info,
    };

    vkGetDescriptorEXT(vk_device, *get_info, image_descriptor_size, element_ptr);
}

write_sampler_descriptor :: (vk_sampler: VkSampler, index: Gpu_Sampler) {
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
}

destroy_bindless_buffer :: () {
    vmaDestroyBuffer(vma, bindless_buffer.vk_buffer, bindless_buffer.allocation);
}

descriptor_properties: VkPhysicalDeviceDescriptorBufferPropertiesEXT;
bindless_set_layout: VkDescriptorSetLayout;
bindless_buffer: struct {
    vk_buffer: VkBuffer;
    allocation: VmaAllocation;
    gpu_ptr: VkDeviceAddress;
    mapped: *void;
};

vkGetDescriptorSetLayoutSizeEXT: PFN_vkGetDescriptorSetLayoutSizeEXT;
vkGetDescriptorSetLayoutBindingOffsetEXT: PFN_vkGetDescriptorSetLayoutBindingOffsetEXT;
vkGetDescriptorEXT: PFN_vkGetDescriptorEXT;
vkCmdBindDescriptorBuffersEXT: PFN_vkCmdBindDescriptorBuffersEXT;
vkCmdSetDescriptorBufferOffsetsEXT: PFN_vkCmdSetDescriptorBufferOffsetsEXT;

align_forward :: (size: VkDeviceSize, align: VkDeviceSize) -> VkDeviceSize {
    return (size + align - 1) & ~(align - 1);
}