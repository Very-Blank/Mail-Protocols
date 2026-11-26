const std = @import("std");
const smtp = @import("smtp");
const Linux = @import("mock").Linux;

pub fn main(init: std.process.Init) !void {
    const allocator: std.mem.Allocator = init.arena.allocator();
    var linux_mock = Linux.init(allocator);
    const mock = linux_mock.interface();

    var smtp_server: smtp.Server = try .init(mock, .{});
    defer smtp_server.deinit(mock);

    try smtp_server.run(mock);
}
