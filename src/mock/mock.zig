const std = @import("std");

ptr: *anyopaque,
vtable: *const VTable,

const Mock = @This();

pub const Error = error{Unexpected};

pub const VTable = struct {
    connect: *const fn (ptr: *anyopaque, port: u16, address: u32) Error!Socket,
    listen: *const fn (ptr: *anyopaque, port: u16, address: u32, backlog: u32) Error!ServerSocket,
};

pub fn connect(self: Mock, port: u16, address: u32) Error!Socket {
    return self.vtable.connect(self.ptr, port, address);
}

pub fn listen(self: Mock, port: u16, address: u32, backlog: u32) Error!ServerSocket {
    return self.vtable.listen(self.ptr, port, address, backlog);
}

pub const Socket = struct {
    ptr: *anyopaque,
    vtable: *const Socket.VTable,

    pub const VTable = struct {
        read: *const fn (socket: *Socket, mock: Mock, buf: []u8) Error!usize,
        write: *const fn (socket: *Socket, mock: Mock, buf: []const u8) Error!usize,
        close: *const fn (socket: *Socket, mock: Mock) void,
    };

    pub fn read(self: *Socket, mock: Mock, buf: []u8) Error!usize {
        return self.vtable.read(self, mock, buf);
    }

    pub fn write(self: *Socket, mock: Mock, buf: []const u8) Error!usize {
        return self.vtable.write(self, mock, buf);
    }

    pub fn close(self: *Socket, mock: Mock) void {
        self.vtable.close(self, mock);
    }
};

pub const ServerSocket = struct {
    ptr: *anyopaque,
    vtable: *const ServerSocket.VTable,

    pub const VTable = struct {
        accept: *const fn (server_socket: *ServerSocket, mock: Mock) Error!Socket,
        close: *const fn (server_socket: *ServerSocket, mock: Mock) void,
    };

    pub fn accept(self: *ServerSocket, mock: Mock) Error!Socket {
        return self.vtable.accept(self, mock);
    }

    pub fn close(self: *ServerSocket, mock: Mock) void {
        self.vtable.close(self, mock);
    }
};
