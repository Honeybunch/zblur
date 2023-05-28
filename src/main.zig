const std = @import("std");
const args_parser = @import("args");
const img = @import("img");
const qoi = @import("qoi");
const vk = @import("vulkan");
const shaders = @import("shaders");
const ComputeContext = @import("compute.zig").ComputeContext;

pub fn main() !void {
    // Setup simple allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const std_alloc = gpa.allocator();

    // Init Vulkan and find a compute capable queue to run on
    var compute = try ComputeContext.init(std_alloc, "zblur");
    defer compute.deinit();

    // Read and Decode QOI image from stdin
    var image = try read_qoi_stdin(std_alloc) orelse return;
    defer image.deinit(std_alloc);

    // Allocate Vulkan controlled buffer for decoded image

    // Write image into buffer

    // Create GPU controlled image to upload to

    // Create GPU image to read back from

    // Record & Submit upload command

    // Create primitives for dispatch

    // Record & Submit dispatch

    // Wait for GPU

    // Read back image data from GPU

    // Encode as QOI
    const qoi_buffer = try qoi.encodeBuffer(std_alloc, image.asConst());
    defer std_alloc.free(qoi_buffer);

    // Write to stdout
    try write_stdout(qoi_buffer);
}

fn read_qoi_stdin(alloc: std.mem.Allocator) !?qoi.Image {
    return blk: {
        const stdin = std.io.getStdIn();
        const stdin_reader = stdin.reader();
        // If stdin is a terminal we can't function
        if (stdin.isTty()) {
            break :blk qoi.DecodeError.EndOfStream;
        }
        const stat = try stdin.stat();
        switch (stat.kind) {
            // We have to know that this was a file pipe
            std.fs.IterableDir.Entry.Kind.File => {
                var buffered_stream = std.io.bufferedReader(stdin_reader);
                // Whether this succeeds or produces an error we will pass that out of the block
                break :blk qoi.decodeStream(alloc, buffered_stream.reader());
            },
            else => {
                break :blk error.Unexpected;
            },
        }
    } catch |err| {
        // Surface known failure modes as human readable messages
        switch (err) {
            qoi.DecodeError.OutOfMemory => {
                try write_stdout("QOI Decoder out of memory. Giving up\n");
            },
            qoi.DecodeError.EndOfStream => {
                try write_stdout("Expected valid input from pipe. Please cat a QOI file into this executable.\n");
            },
            qoi.DecodeError.InvalidData => {
                try write_stdout("Invalid data provided. Did you pipe in a well formed QOI file?\n");
            },
            else => {
                // On an unexpected error return err so that the callstack will surface
                try write_stdout("Unexpected failure mode!\n");
                return err;
            },
        }
        // No matter what we return null if we got an error
        return null;
    };
}

fn write_stdout(data: []const u8) !void {
    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();
    _ = try w.write(data);
    try buf.flush();
}
