const std = @import("std");
const linux = std.os.linux;

const Mock = @import("mock.zig");

const LinuxMock = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) LinuxMock {
    return .{
        .allocator = allocator,
    };
}

/// Don't move the LinuxMock after calling this, the returned Mock points at it.
pub fn interface(self: *LinuxMock) Mock {
    return .{ .ptr = self, .vtable = &mock_vtable };
}

const mock_vtable: Mock.VTable = .{
    .listen = LinuxMock.listen,
    .connect = LinuxMock.connect,
};

const socket_vtable: Mock.Socket.VTable = .{
    .read = Socket.read,
    .write = Socket.write,
    .close = Socket.close,
};

const server_socket_vtable: Mock.ServerSocket.VTable = .{
    .accept = ServerSocket.accept,
    .close = ServerSocket.close,
};

const ServerSocket = struct {
    fd: linux.fd_t,

    pub fn accept(server_socket: *Mock.ServerSocket, mock: Mock) Mock.Error!Mock.Socket {
        const linux_mock: *LinuxMock = @ptrCast(@alignCast(mock.ptr));
        const linux_socket: *Socket = @ptrCast(@alignCast(server_socket.ptr));

        const result = linux.accept(linux_socket.fd, null, null);

        if (linux.errno(result) != .SUCCESS)
            return Mock.Error.Unexpected;

        const ptr: *Socket = linux_mock.allocator.create(Socket) catch @panic("OOM");

        ptr.* = .{
            .fd = @intCast(result),
        };

        return .{
            .ptr = @ptrCast(ptr),
            .vtable = &socket_vtable,
        };
    }

    pub fn close(server_socket: *Mock.ServerSocket, mock: Mock) void {
        const linux_mock: *LinuxMock = @ptrCast(@alignCast(mock.ptr));
        const linux_socket: *ServerSocket = @ptrCast(@alignCast(server_socket.ptr));

        _ = linux.shutdown(linux_socket.fd, linux.SHUT.RDWR);
        _ = linux.close(linux_socket.fd);
        linux_mock.allocator.destroy(linux_socket);
        server_socket.ptr = undefined;
    }
};

const Socket = struct {
    fd: linux.fd_t,

    pub fn read(socket: *Mock.Socket, mock: Mock, buf: []u8) Mock.Error!usize {
        _ = mock;
        const linux_socket: *Socket = @ptrCast(@alignCast(socket.ptr));
        while (true) {
            const result = linux.read(linux_socket.fd, buf.ptr, buf.len);
            switch (linux.errno(result)) {
                .SUCCESS => return result,
                .INTR => continue,
                else => return Mock.Error.Unexpected,
            }
        }
    }

    pub fn write(socket: *Mock.Socket, mock: Mock, buf: []const u8) Mock.Error!usize {
        _ = mock;
        const linux_socket: *Socket = @ptrCast(@alignCast(socket.ptr));

        while (true) {
            const result = linux.write(linux_socket.fd, buf.ptr, buf.len);
            switch (linux.errno(result)) {
                .SUCCESS => return result,
                .INTR => continue,
                else => return Mock.Error.Unexpected,
            }
        }
    }

    pub fn close(socket: *Mock.Socket, mock: Mock) void {
        const linux_mock: *LinuxMock = @ptrCast(@alignCast(mock.ptr));
        const linux_socket: *Socket = @ptrCast(@alignCast(socket.ptr));

        _ = linux.close(linux_socket.fd);
        linux_mock.allocator.destroy(linux_socket);
        socket.ptr = undefined;
    }
};

pub fn listen(mock_ptr: *anyopaque, port: u16, address: u32, backlog: u32) Mock.Error!Mock.ServerSocket {
    const linux_mock: *LinuxMock = @ptrCast(@alignCast(mock_ptr));

    const socket: linux.fd_t = init: {
        const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);

        if (linux.errno(result) != .SUCCESS)
            return Mock.Error.Unexpected;

        break :init @intCast(result);
    };

    errdefer _ = linux.close(socket);

    if (linux.errno(
        linux.bind(
            socket,
            @ptrCast(&linux.sockaddr.in{
                .port = std.mem.nativeToBig(u16, port),
                .addr = address,
            }),
            @sizeOf(linux.sockaddr.in),
        ),
    ) != .SUCCESS)
        return Mock.Error.Unexpected;

    if (linux.errno(
        linux.listen(
            socket,
            backlog,
        ),
    ) != .SUCCESS)
        return Mock.Error.Unexpected;

    const ptr: *ServerSocket = linux_mock.allocator.create(ServerSocket) catch @panic("OOM");

    ptr.* = .{
        .fd = @intCast(socket),
    };

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = &server_socket_vtable,
    };
}

pub fn connect(mock_ptr: *anyopaque, port: u16, address: u32) Mock.Error!Mock.Socket {
    const linux_mock: *LinuxMock = @ptrCast(@alignCast(mock_ptr));

    const socket: linux.fd_t = init: {
        const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);

        if (linux.errno(result) != .SUCCESS)
            return Mock.Error.Unexpected;

        break :init @intCast(result);
    };

    errdefer _ = linux.close(socket);

    if (linux.errno(linux.connect(
        socket,
        @ptrCast(&linux.sockaddr.in{
            .port = std.mem.nativeToBig(u16, port),
            .addr = address,
        }),
        @sizeOf(linux.sockaddr.in),
    )) != .SUCCESS)
        return Mock.Error.Unexpected;

    const ptr: *Socket = linux_mock.allocator.create(Socket) catch @panic("OOM");

    ptr.* = .{
        .fd = @intCast(socket),
    };

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = &socket_vtable,
    };
}
