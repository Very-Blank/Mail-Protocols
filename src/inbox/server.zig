const std = @import("std");
const smtp = @import("smtp");
const linux = std.os.linux;

const Inbox = @import("root.zig").Inbox;
const Path = smtp.Path;
const User = smtp.User;

port: u16 = std.mem.nativeToBig(u16, 6001),
address: u32 = @bitCast([4]u8{ 127, 0, 0, 1 }),
socket: linux.fd_t,
inbox: Inbox,

const Self = @This();

pub const Post = struct {
    receiver: User,
    sender: Path,
    data: []const u8,
};

pub fn init(
    address: struct {
        port: u16 = std.mem.nativeToBig(u16, 6001),
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
        .inbox = try .init(.{ .file = null }),
        .port = address.port,
        .address = address.address,
        .socket = socket,
    };
}

pub fn deinit(self: *Self) void {
    _ = linux.shutdown(self.socket, linux.SHUT.RDWR);
    _ = linux.close(self.socket);
}

pub fn run(self: *Self, allocator: std.mem.Allocator) !void {
    var buffer: []u8 = &.{};
    defer {
        if (buffer.len != 0) {
            allocator.free(buffer);
        }
    }

    while (true) {
        // SANITIZE
        for (0..buffer.len) |i| {
            buffer[i] = 0;
        }

        std.debug.print("Waiting for client to connect\n", .{});

        const socket: linux.fd_t, _ = init: {
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
                @intCast(result),
                details,
            };
        };

        defer {
            _ = linux.shutdown(socket, linux.SHUT.RDWR);
            _ = linux.close(socket);
        }

        std.debug.print("Client connected\n", .{});

        var command_buffer: [8]u8 = @splat(0);
        try read(socket, &command_buffer);

        const command: []const u8 = command_buffer[0..4];
        const length: u32 = std.mem.bytesToValue(u32, command_buffer[4..]);

        // NOTE: This is very inefficient, but it's quick to implement it so...
        if (std.mem.eql(u8, command, "POST")) {
            buffer = try allocator.realloc(buffer, length);
            try read(socket, buffer);

            const parsed_json: std.json.Parsed(Post) = try std.json.parseFromSlice(Post, allocator, buffer, .{});
            defer parsed_json.deinit();

            try self.inbox.addMessage(parsed_json.value.receiver, parsed_json.value.sender, parsed_json.value.data);
        } else if (std.mem.eql(u8, command, "READ")) {
            buffer = try allocator.realloc(buffer, length);
            try read(socket, buffer);

            const parsed_json: std.json.Parsed(User) = try std.json.parseFromSlice(User, allocator, buffer, .{});
            defer parsed_json.deinit();

            const messages = try self.inbox.getMessages(allocator, parsed_json.value);

            defer {
                for (messages) |capture| {
                    allocator.free(capture.data);
                    allocator.free(capture.sender);
                }

                allocator.free(messages);
            }

            var allocating_writer = std.Io.Writer.Allocating.init(allocator);
            defer allocating_writer.deinit();

            const fmt = std.json.fmt(messages, .{});
            try fmt.format(&allocating_writer.writer);

            const data = allocating_writer.written();

            if (linux.errno(linux.write(socket, data.ptr, data.len)) != .SUCCESS)
                return error.WriteFailed;
        } else {
            // FIXME: ERROR CLIENT IS BEING BADDY
        }

        std.debug.print("Client disconnected\n", .{});
    }
}

/// Reads until the buffer is full
pub fn read(socket: linux.fd_t, buffer: []u8) !void {
    std.debug.assert(buffer.len != 0);

    var slice = buffer;
    var length: usize = 0;

    while (length < buffer.len) {
        const result = linux.read(
            socket,
            buffer.ptr,
            buffer.len,
        );

        if (linux.errno(result) != .SUCCESS) {
            return error.FailedToRead;
        }

        length += result;
        slice = buffer[length..];
    }
}
