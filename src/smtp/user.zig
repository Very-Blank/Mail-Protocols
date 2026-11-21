const std = @import("std");

buffer: [max_len]u8 = @splat(0),
len: u8 = 0,

const Self = @This();

// https://www.rfc-editor.org/info/rfc821/#page-42
pub const max_len = 64;

pub inline fn get(self: *const Self) []const u8 {
    std.debug.assert(0 < self.len and self.len <= max_len);
    return self.buffer[0..self.len];
}

pub inline fn parse(buffer: []const u8) !Self {
    std.debug.assert(buffer.len != 0);

    if (max_len < buffer.len)
        return error.InvalidCommand;

    for (buffer, 0..) |c, i| {
        if (std.ascii.isAlphanumeric(c))
            continue;

        if (c == '.' and i + 1 < buffer.len and
            std.ascii.isAlphanumeric(buffer[i + 1]))
            continue;

        return error.InvalidCommand;
    }

    var domain: Self = .{
        .len = @intCast(buffer.len),
    };

    @memcpy(domain.buffer[0..buffer.len], buffer);

    return domain;
}
