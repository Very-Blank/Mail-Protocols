const std = @import("std");
const Mock = @import("mock").Mock;

const Client = @import("client.zig");

port: u16,
address: u32,
socket: Mock.ServerSocket,
max_iterations: union(enum) { none: void, count: usize } = .{ .none = {} },

const Self = @This();

pub fn init(
    mock: Mock,
    address: struct {
        port: u16 = 6000,
        address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
    },
) !Self {
    return .{
        .port = address.port,
        .address = address.address,
        .socket = try mock.listen(address.port, address.address, 1),
    };
}

pub fn deinit(self: *Self, mock: Mock) void {
    self.socket.close(mock);
}

pub fn run(self: *Self, mock: Mock) !void {
    var iterations: usize = 0;
    while (switch (self.max_iterations) {
        .count => |count| if (iterations < count) true else false,
        .none => true,
    }) : (iterations +%= 1) {
        std.debug.print("Waiting for client to connect\n", .{});

        var client: Client = .{
            .socket = try self.socket.accept(mock),
        };

        std.debug.print("Client connected\n", .{});

        try client.serve(mock);
        defer client.deinit(mock);

        std.debug.print("Client disconnected\n", .{});
    }
}

test "TEST!" {
    const Test = @import("mock").Test;
    const allocator: std.mem.Allocator = std.testing.allocator;

    var buffer1: [256]u8 = @splat(0);
    var buffer2: [256]u8 = @splat(0);
    var buffer3: [256]u8 = @splat(0);

    var test_mock: Test = .{
        .listening_sockets = &.{
            .{
                .sockets = &.{
                    Test.Socket{
                        .read_buffers = &.{"QUIT\r\n"},
                        .write_buffers = &.{
                            &buffer1,
                            &buffer2,
                            &buffer3,
                        },
                    },
                },
                .address = @bitCast([4]u8{ 127, 0, 0, 1 }),
                .port = 6000,
            },
        },
        .connecting_sockets = &.{},
        .allocator = allocator,
    };

    const mock = test_mock.interface();

    var smtp_server: Self = try .init(mock, .{});
    smtp_server.max_iterations = .{ .count = 1 };
    defer smtp_server.deinit(mock);

    try smtp_server.run(mock);

    std.debug.print("{s}", .{buffer1});
    std.debug.print("{s}", .{buffer2});
}
