const std = @import("std");
const linux = std.os.linux;

pub const Inbox = @import("inbox.zig");
pub const Server = @import("server.zig");
pub const Post = Server.Post;

pub fn addMessage(
    allocator: std.mem.Allocator,
    receiver: User,
    sender: Path,
    data: []const u8,
    address: struct {
        port: u16 = std.mem.nativeToBig(u16, 6001),
        address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
    },
) !void {
    const socket: linux.fd_t = init: {
        const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);

        if (linux.errno(result) != .SUCCESS)
            return error.FailedToCreateSocket;

        break :init @intCast(result);
    };

    defer linux.close(socket);

    if (linux.errno(linux.connect(
        socket,
        @ptrCast(&linux.sockaddr.in{
            .port = address.port,
            .addr = address.address,
        }),
        @sizeOf(linux.sockaddr.in),
    )) != .SUCCESS)
        return error.FailedToConnect;

    var allocating_writer = std.Io.Writer.Allocating.init(allocator);
    defer allocating_writer.deinit();

    const fmt = std.json.fmt(messages, .{});
    try fmt.format(&allocating_writer.writer);

    const data = allocating_writer.written();

    // We repalce the ???? with the actuall length.
    var command: [8]u8 = "POST????";
    std.mem.writeInt(u32, buffer[4..], @intCast(data.len), .little);

    if (linux.errno(linux.write(socket, command, command.len)) != .SUCCESS)
        return error.WriteFailed;

    if (linux.errno(linux.write(socket, data.ptr, data.len)) != .SUCCESS)
        return error.WriteFailed;
}

test "All for one!" {
    _ = @import("server.zig");
    _ = @import("inbox.zig");
}
