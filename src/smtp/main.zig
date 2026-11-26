const std = @import("std");
const smtp = @import("smtp");
const LinuxMock = @import("mock").LinuxMock;

const linux = std.os.linux;

pub fn main(init: std.process.Init) !void {
    const allocator: std.mem.Allocator = init.arena.allocator();
    var linux_mock = LinuxMock.init(allocator);
    const mock = linux_mock.interface();

    var smtp_server: smtp.Server = try .init(mock, .{});
    defer smtp_server.deinit(mock);

    try smtp_server.run(mock);
}
