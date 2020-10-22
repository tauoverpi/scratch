const std = @import("std");
const testing = std.testing;
const prep = std.log.scoped(.@"🚀 assembly");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

pub fn main() !void {
    _ = c.glfwInit();
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    var window = c.glfwCreateWindow(800, 600, "rocketvk", null, null) orelse
        return error.UnableToAllocateWindow;
    defer c.glfwDestroyWindow(window);

    var extensions: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &extensions, null);

    prep.info("extensions {}", .{extensions});

    var app_info = std.mem.zeroes(c.VkApplicationInfo);
    app_info.sType = @intToEnum(@TypeOf(app_info.sType), c.VK_STRUCTURE_TYPE_APPLICATION_INFO);
    app_info.pApplicationName = "RocketVk";
    app_info.applicationVersion = c.VK_MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = c.VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = c.VK_API_VERSION_1_0;
    app_info.pNext = null;

    var glfw_ext_count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    var create_info = std.mem.zeroes(c.VkInstanceCreateInfo);
    create_info.sType = @intToEnum(@TypeOf(create_info.sType), c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO);
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = glfw_ext_count;
    create_info.ppEnabledExtensionNames = glfw_exts;
    create_info.enabledLayerCount = 0;
    create_info.pNext = null;

    var instance: c.VkInstance = undefined;

    if (@enumToInt(c.vkCreateInstance(&create_info, null, &instance)) != c.VK_SUCCESS)
        return error.FailedToCreateInstance;

    {
        var ext_count: u32 = 0;
        _ = c.vkEnumerateInstanceExtensionProperties(null, &ext_count, null);
        var props = try std.heap.page_allocator.alloc(c.VkExtensionProperties, ext_count);
        defer std.heap.page_allocator.free(props);
        _ = c.vkEnumerateInstanceExtensionProperties(null, &ext_count, props.ptr);
        for (props) |prop| prep.info("ext {}", .{prop.extensionName});
    }

    var physical_device = std.mem.zeroes(c.VkPhysicalDevice);
    const QueueFamilyIndices = struct {
        graphics: ?u32 = null,
        present: ?u32 = null,
    };

    var surface = std.mem.zeroes(c.VkSurfaceKHR);

    if (@enumToInt(c.glfwCreateWindowSurface(instance, window, null, &surface)) != c.VK_SUCCESS)
        return error.CannotCreateSurface;
    defer c.vkDestroySurfaceKHR(instance, surface, null);

    var indices: QueueFamilyIndices = .{};

    {
        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(instance, &device_count, null);
        if (device_count == 0) return error.NoVulkanSupport;
        var devices = try std.heap.page_allocator.alloc(c.VkPhysicalDevice, device_count);
        defer std.heap.page_allocator.free(devices);
        _ = c.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);
        for (devices) |device| {
            if (device) |dev| {
                var features: c.VkPhysicalDeviceFeatures = undefined;
                c.vkGetPhysicalDeviceFeatures(dev, &features);

                var queue_count: u32 = 0;
                c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_count, null);
                var queues = try std.heap.page_allocator.alloc(c.VkQueueFamilyProperties, queue_count);
                defer std.heap.page_allocator.free(queues);
                c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_count, queues.ptr);

                for (queues) |queue, i| {
                    var present: c.VkBool32 = c.VK_FALSE;
                    _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(dev, @truncate(u32, i), surface, &present);
                    if (present == c.VK_TRUE) indices.present = @truncate(u32, i);
                    if (queue.queueFlags & @intCast(u32, c.VK_QUEUE_GRAPHICS_BIT) > 0) {
                        indices.graphics = @truncate(u32, i);
                    }
                }

                if (features.geometryShader == 1 and indices.graphics != null) {
                    physical_device = dev;
                    break;
                } else indices = .{};
            }
        } else return error.FailedToFindADevice;
    }

    prep.info("{}", .{indices});

    var graphics_queue_priority: f32 = 1.0;
    var queue_info = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
    queue_info.sType = @intToEnum(@TypeOf(queue_info.sType), c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO);
    queue_info.queueFamilyIndex = indices.graphics.?;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &graphics_queue_priority;
    queue_info.pNext = null;

    var queue_present_info = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
    queue_present_info.sType = @intToEnum(@TypeOf(queue_present_info.sType), c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO);
    queue_present_info.queueFamilyIndex = indices.present.?;
    queue_present_info.queueCount = 1;
    queue_present_info.pQueuePriorities = &graphics_queue_priority;
    queue_present_info.pNext = &queue_info;

    var device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

    var device_info = std.mem.zeroes(c.VkDeviceCreateInfo);
    device_info.sType = @intToEnum(@TypeOf(device_info.sType), c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO);
    device_info.pQueueCreateInfos = &queue_present_info;
    device_info.queueCreateInfoCount = 1;
    device_info.pEnabledFeatures = &device_features;

    var device = std.mem.zeroes(c.VkDevice);

    if (@enumToInt(c.vkCreateDevice(physical_device, &device_info, null, &device)) != c.VK_SUCCESS)
        return error.CannotCreateLogicalDevice;

    //while (c.glfwWindowShouldClose(window) == 0) {
    //glfwPollEvents();
    //}
}
