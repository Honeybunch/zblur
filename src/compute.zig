const std = @import("std");
const vk = @import("vulkan");
const volk = @import("volk.zig");

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSemaphore = true,
    .createFence = true,
    .createImageView = true,
    .destroyImageView = true,
    .destroySemaphore = true,
    .destroyFence = true,
    .deviceWaitIdle = true,
    .waitForFences = true,
    .resetFences = true,
    .queueSubmit = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .queueWaitIdle = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .destroyPipeline = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .allocateMemory = true,
    .freeMemory = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .mapMemory = true,
    .unmapMemory = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindPipeline = true,
    .cmdDraw = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
    .cmdDispatch = true,
});

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkd: DeviceDispatch, dev: vk.Device, family: u32) Queue {
        return .{
            .handle = vkd.getDeviceQueue(dev, family, 0),
            .family = family,
        };
    }
};

const QueueAllocation = struct {
    compute_family: u32,
};

const DeviceCandidate = struct {
    gpu: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

pub const ComputeContext = struct {
    vkb: BaseDispatch,
    vki: InstanceDispatch,
    vkd: DeviceDispatch,

    instance: vk.Instance,
    gpu: vk.PhysicalDevice,
    gpu_props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: vk.Device,
    compute_queue: Queue,

    pub fn init(allocator: std.mem.Allocator, app_name: [*:0]const u8) !ComputeContext {
        var self: ComputeContext = undefined;

        volk.init();

        self.vkb = try BaseDispatch.load(volk.getInstanceProcAddress);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = app_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        };

        self.instance = try self.vkb.createInstance(&.{
            .p_application_info = &app_info,
        }, null);

        volk.loadInstance(self.instance);

        self.vki = try InstanceDispatch.load(self.instance, volk.getInstanceProcAddress);
        errdefer self.vki.destroyInstance(self.instance, null);

        const candidate = try pickGPU(self.vki, self.instance, allocator);
        self.gpu = candidate.gpu;
        self.gpu_props = candidate.props;
        self.dev = try initializeCandidate(self.vki, candidate);
        self.vkd = try DeviceDispatch.load(self.dev, self.vki.dispatch.vkGetDeviceProcAddr);
        errdefer self.vkd.destroyDevice(self.dev, null);

        self.compute_queue = Queue.init(self.vkd, self.dev, candidate.queues.compute_family);

        self.mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.gpu);

        return self;
    }

    pub fn deinit(self: ComputeContext) void {
        self.vkd.destroyDevice(self.dev, null);
        self.vki.destroyInstance(self.instance, null);
    }

    fn initializeCandidate(vki: InstanceDispatch, candidate: DeviceCandidate) !vk.Device {
        const priority = [_]f32{1};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = candidate.queues.compute_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        return try vki.createDevice(candidate.gpu, &.{
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
        }, null);
    }

    fn pickGPU(
        vki: InstanceDispatch,
        instance: vk.Instance,
        allocator: std.mem.Allocator,
    ) !DeviceCandidate {
        var device_count: u32 = undefined;
        _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);

        const gpus = try allocator.alloc(vk.PhysicalDevice, device_count);
        defer allocator.free(gpus);

        _ = try vki.enumeratePhysicalDevices(instance, &device_count, gpus.ptr);

        for (gpus) |gpu| {
            if (try checkSuitable(vki, gpu, allocator)) |candidate| {
                return candidate;
            }
        }

        return error.NoSuitableDevice;
    }

    fn checkSuitable(
        vki: InstanceDispatch,
        gpu: vk.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !?DeviceCandidate {
        const props = vki.getPhysicalDeviceProperties(gpu);

        if (try allocateQueues(vki, gpu, allocator)) |allocation| {
            return DeviceCandidate{
                .gpu = gpu,
                .props = props,
                .queues = allocation,
            };
        }

        return null;
    }

    fn allocateQueues(vki: InstanceDispatch, gpu: vk.PhysicalDevice, allocator: std.mem.Allocator) !?QueueAllocation {
        var family_count: u32 = undefined;
        vki.getPhysicalDeviceQueueFamilyProperties(gpu, &family_count, null);

        const families = try allocator.alloc(vk.QueueFamilyProperties, family_count);
        defer allocator.free(families);
        vki.getPhysicalDeviceQueueFamilyProperties(gpu, &family_count, families.ptr);

        var compute_family: ?u32 = null;

        for (families, 0..) |properties, i| {
            const family = @intCast(u32, i);

            if (compute_family == null and properties.queue_flags.compute_bit) {
                compute_family = family;
            }
        }

        if (compute_family != null) {
            return QueueAllocation{
                .compute_family = compute_family.?,
            };
        }

        return null;
    }
};
