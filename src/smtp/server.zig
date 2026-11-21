const std = @import("std");
const linux = std.os.linux;

const Client = @import("client.zig");

port: u16 = std.mem.nativeToBig(u16, 6000),
address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
socket: linux.fd_t,

const Self = @This();

pub fn init(
    address: struct {
        port: u16 = std.mem.nativeToBig(u16, 6000),
        address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
    },
) !Self {
    const socket: linux.fd_t = init: {
        const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);

        if (linux.errno(result) != .SUCCESS)
            return error.FailedToCreateSocket;

        break :init @intCast(result);
    };

    errdefer _ = linux.close(socket);

    if (linux.errno(
        linux.bind(
            socket,
            @ptrCast(&linux.sockaddr.in{
                .port = address.port,
                .addr = address.address,
            }),
            @sizeOf(linux.sockaddr.in),
        ),
    ) != .SUCCESS)
        return error.FailedToBind;

    if (linux.errno(
        linux.listen(
            socket,
            1,
        ),
    ) != .SUCCESS)
        return error.FailedToListen;

    return .{
        .port = address.port,
        .address = address.address,
        .socket = socket,
    };
}

pub fn deinit(self: *const Self) void {
    _ = linux.shutdown(self.socket, linux.SHUT.RDWR);
    _ = linux.close(self.socket);
}

pub fn run(self: *Self) !void {
    while (true) {
        std.debug.print("Waiting for client to connect\n", .{});

        var client: Client = init: {
            var details: linux.sockaddr.in = undefined;
            var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);

            const result = linux.accept(
                self.socket,
                @ptrCast(&details),
                &len,
            );

            if (linux.errno(result) != .SUCCESS)
                return error.FailedToAccept;

            break :init .{
                .socket = @intCast(result),
                .details = details,
            };
        };

        std.debug.print("Client connected\n", .{});

        try client.serve();
        defer client.deinit();

        std.debug.print("Client disconnected\n", .{});
    }
}
