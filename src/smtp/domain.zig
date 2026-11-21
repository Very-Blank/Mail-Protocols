const std = @import("std");

buffer: [max_len]u8 = @splat(0),
len: u8 = 0,

const Self = @This();

pub const max_len = 64;

pub inline fn get(self: *const Self) []const u8 {
    std.debug.assert(0 < self.len and self.len <= max_len);
    return self.buffer[0..self.len];
}

// FIXME: Check validity
pub inline fn parse(buffer: []const u8) !Self {
    std.debug.assert(buffer.len != 0);

    if (max_len < buffer.len)
        return error.InvalidCommand;

    var domain: Self = .{
        .len = @intCast(buffer.len),
    };

    @memcpy(domain.buffer[0..buffer.len], buffer);

    return domain;
}
