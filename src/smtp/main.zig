const std = @import("std");
const smtp = @import("smtp");

const linux = std.os.linux;

pub fn main(_: std.process.Init) !void {
    var smtp_server: smtp.Server = try .init(.{});
    defer smtp_server.deinit();

    try smtp_server.run();
}
