const std = @import("std");
const Mock = @import("mock").Mock;

const Client = @import("client.zig");

port: u16 = std.mem.nativeToBig(u16, 6000),
address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
socket: Mock.ServerSocket,

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
    while (true) {
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
