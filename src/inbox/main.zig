const std = @import("std");
const inbox = @import("inbox");

const linux = std.os.linux;

pub fn main(_: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;

    var inbox_server: inbox.Server = try .init(.{});
    defer inbox_server.deinit();

    try inbox_server.run(allocator);
}
