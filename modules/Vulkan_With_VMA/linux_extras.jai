#scope_export

VkXlibSurfaceCreateFlagsKHR :: VkFlags;

VkXlibSurfaceCreateInfoKHR :: struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
    pNext: *void;
    flags: VkXlibSurfaceCreateFlagsKHR;
    display: *Display;
    window: Window;
}

PFN_vkCreateXlibSurfaceKHR :: #type (instance: VkInstance, pCreateInfo: *VkXlibSurfaceCreateInfoKHR, pAllocator: *VkAllocationCallbacks, surface: *VkSurfaceKHR) -> VkResult #c_call;

VkWaylandSurfaceCreateInfoKHR :: struct {
    sType:   VkStructureType = .VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
    pNext:   *void;
    flags:   VkFlags;
    display: *void;
    surface: *void;
}

PFN_vkCreateWaylandSurfaceKHR :: #type (instance: VkInstance, pCreateInfo: *VkWaylandSurfaceCreateInfoKHR, pAllocator: *VkAllocationCallbacks, surface: *VkSurfaceKHR) -> VkResult #c_call;
PFN_vkGetPhysicalDeviceWaylandPresentationSupportKHR :: #type (physicalDevice: VkPhysicalDevice, queueFamilyIndex: u32, display: *void) -> VkBool32 #c_call;

#scope_file

#import "X11";
