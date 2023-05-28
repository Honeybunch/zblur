pub usingnamespace @cImport({
    @cInclude("volk.h");
});

const vk = @import("vulkan");

const volk = @This();

pub fn init() void {
    _ = volk.volkInitialize();
}

pub fn getInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
    if (volk.vkGetInstanceProcAddr) |GetInstanceProcAddr| {
        if (instance == vk.Instance.null_handle) {
            return GetInstanceProcAddr(null, procname);
        } else {
            return GetInstanceProcAddr(@alignCast(@alignOf([*c]*volk.struct_VkInstance_T), @intToPtr(*volk.struct_VkInstance_T, @enumToInt(instance))), procname);
        }
    }
    return null;
}

pub fn loadInstance(instance: vk.Instance) void {
    volk.volkLoadInstance(@alignCast(@alignOf([*c]*volk.struct_VkInstance_T), @intToPtr(*volk.struct_VkInstance_T, @enumToInt(instance))));
}
