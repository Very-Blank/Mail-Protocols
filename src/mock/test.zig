const std = @import("std");
const linux = std.os.linux;

const Mock = @import("mock.zig");

const Test = @This();

listening_sockets: []const ServerSocket,
connecting_sockets: []const Socket,
allocator: std.mem.Allocator,

// pub fn init(allocator: std.mem.Allocator) Test {
//     return .{
//         .allocator = allocator,
//     };
// }

/// Moving Test after getting the interface is undefined behaviour.
pub fn interface(self: *Test) Mock {
    return .{ .ptr = self, .vtable = &vtable };
}

const vtable: Mock.VTable = .{
    .listen = Test.listen,
    .connect = Test.connect,
};

pub const ServerSocket = struct {
    sockets: []const Socket,
    accepts: usize = 0,
    address: u32,
    port: u16,

    const vtable: Mock.ServerSocket.VTable = .{
        .accept = ServerSocket.accept,
        .close = ServerSocket.close,
    };

    pub fn accept(server_socket: *Mock.ServerSocket, mock: Mock) Mock.Error!Mock.Socket {
        const test_mock: *Test = @ptrCast(@alignCast(mock.ptr));
        const test_socket: *ServerSocket = @ptrCast(@alignCast(server_socket.ptr));

        defer test_socket.accepts += 1;

        const socket = if (test_socket.accepts < test_socket.sockets.len) test_socket.sockets[test_socket.accepts] else @panic("Not implemented");

        const ptr: *Socket = test_mock.allocator.create(Socket) catch @panic("OOM");

        ptr.* = socket;

        return .{
            .ptr = @ptrCast(ptr),
            .vtable = &Socket.vtable,
        };
    }

    pub fn close(server_socket: *Mock.ServerSocket, mock: Mock) void {
        const test_mock: *Test = @ptrCast(@alignCast(mock.ptr));
        const test_socket: *ServerSocket = @ptrCast(@alignCast(server_socket.ptr));

        test_mock.allocator.destroy(test_socket);
        server_socket.ptr = undefined;
    }
};

pub const Socket = struct {
    read_buffers: []const []const u8,
    write_buffers: []const []u8,
    reads: usize = 0,
    writes: usize = 0,
    address: u32 = 0,
    port: u16 = 0,

    const vtable: Mock.Socket.VTable = .{
        .read = Socket.read,
        .write = Socket.write,
        .close = Socket.close,
    };

    pub fn read(socket: *Mock.Socket, mock: Mock, buf: []u8) Mock.Error!usize {
        _ = mock;
        const test_socket: *Socket = @ptrCast(@alignCast(socket.ptr));

        defer test_socket.reads += 1;

        const buffer = if (test_socket.reads < test_socket.read_buffers.len) test_socket.read_buffers[test_socket.reads] else @panic("Not implemented");
        const length = @min(buf.len, buffer.len);

        @memcpy(buf[0..length], buffer[0..length]);

        return length;
    }

    pub fn write(socket: *Mock.Socket, mock: Mock, buf: []const u8) Mock.Error!usize {
        _ = mock;
        const test_socket: *Socket = @ptrCast(@alignCast(socket.ptr));

        defer test_socket.writes += 1;

        const buffer = if (test_socket.writes < test_socket.write_buffers.len) test_socket.write_buffers[test_socket.writes] else @panic("Not implemented");
        const length = @min(buf.len, buffer.len);

        @memcpy(buffer[0..length], buf[0..length]);

        return length;
    }

    pub fn close(socket: *Mock.Socket, mock: Mock) void {
        const test_mock: *Test = @ptrCast(@alignCast(mock.ptr));
        const test_socket: *Socket = @ptrCast(@alignCast(socket.ptr));

        test_mock.allocator.destroy(test_socket);
        socket.ptr = undefined;
    }
};

pub fn listen(mock_ptr: *anyopaque, port: u16, address: u32, backlog: u32) Mock.Error!Mock.ServerSocket {
    const test_mock: *Test = @ptrCast(@alignCast(mock_ptr));
    _ = backlog;

    const socket = init: {
        for (test_mock.listening_sockets) |socket| {
            if (port == socket.port and address == socket.address)
                break :init socket;
        }

        @panic("Socket didn't exist");
    };

    const ptr: *ServerSocket = test_mock.allocator.create(ServerSocket) catch @panic("OOM");
    ptr.* = socket;

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = &ServerSocket.vtable,
    };
}

pub fn connect(mock_ptr: *anyopaque, port: u16, address: u32) Mock.Error!Mock.Socket {
    const test_mock: *Test = @ptrCast(@alignCast(mock_ptr));

    const socket = init: {
        for (test_mock.connecting_sockets) |socket| {
            if (port == socket.port and address == socket.address)
                break :init socket;
        }

        @panic("Socket didn't exist");
    };

    const ptr: *Socket = test_mock.allocator.create(Socket) catch @panic("OOM");

    ptr.* = socket;

    return .{
        .ptr = @ptrCast(ptr),
        .vtable = &Socket.vtable,
    };
}
