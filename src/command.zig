const std = @import("std");
const linux = std.os.linux;

const Domain = @import("domain.zig");
const Path = @import("path.zig");

pub const CommandType = enum {
    // https://www.rfc-editor.org/info/rfc821/#section-4.1
    HELO, // HELO <SP> <domain> <CRLF>
    MAIL, // MAIL <SP> FROM:<reverse-path> <CRLF>
    RCPT, // RCPT <SP> TO:<forward-path> <CRLF>
    DATA, // DATA <CRLF>
    QUIT, // QUIT <CRLF>

    const Self = @This();

    pub fn parse(buffer: [4]u8) !Self {
        inline for (@typeInfo(Self).@"enum".field_names) |name| {
            // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
            if (std.ascii.eqlIgnoreCase(name, &buffer))
                return @field(Self, name);
        }

        return error.InvalidCommand;
    }
};

pub const Command = union(CommandType) {
    HELO: Domain,
    MAIL: Path,
    RCPT: Path,
    DATA: void,
    QUIT: void,

    pub fn parse(raw: []const u8) !Command {
        std.debug.assert(std.mem.eql(u8, raw[raw.len - 2 ..], &.{ '\r', '\n' }));
        const buffer: []const u8 = raw[0 .. raw.len - 2];

        if (buffer.len < 4)
            return error.InvalidCommand;

        const command: CommandType = try .parse(buffer[0..4].*);

        switch (command) {
            // HELO <SP> <domain> <CRLF>
            .HELO => {
                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Shortest valid domain is:
                // "#" <number>
                // NOTE: Used an array since it ensures there a exactly the characters we want.
                if (buffer.len < (.{ 'H', 'E', 'L', 'O', ' ', '#', '0' }).len)
                    return error.InvalidCommand;

                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Must have at least on space!
                if (buffer[4] != ' ')
                    return error.NoSeperator;

                const start: usize = init: {
                    for (buffer[5..], 5..) |c, i| {
                        switch (c) {
                            ' ' => {},
                            else => break :init i,
                        }
                    }

                    return error.InvalidCommand;
                };

                if (buffer.len < start + (.{ '#', '1' }).len)
                    // No domain
                    return error.InvalidCommand;

                return .{
                    .HELO = try Domain.parse(buffer[start..]),
                };
            },
            // MAIL <SP> FROM:<reverse-path> <CRLF>
            .MAIL => {
                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Shortest valid reverse-path is:
                // "<" <c> "@" "#" <number> ">"
                if (buffer.len < (.{ 'M', 'A', 'I', 'L', ' ', 'F', 'R', 'O', 'M', ':', '<', 'a', '@', '#', '0', '>' }).len)
                    return error.InvalidCommand;

                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Must have at least on space!
                if (buffer[4] != ' ')
                    return error.NoSeperator;

                const start: usize = init: {
                    for (buffer[5..], 5..) |c, i| {
                        switch (c) {
                            ' ' => {},
                            else => break :init i,
                        }
                    }

                    return error.InvalidCommand;
                };

                if (buffer.len < start + (.{ 'F', 'R', 'O', 'M', ':', '<', 'a', '@', '#', '0', '>' }).len)
                    // Missing rest of the command.
                    return error.InvalidCommand;

                if (!std.ascii.eqlIgnoreCase(
                    buffer[start .. start + (.{ 'F', 'R', 'O', 'M', ':', '<' }).len],
                    &.{ 'F', 'R', 'O', 'M', ':', '<' },
                ) and
                    buffer[buffer.len - 1] != '>')
                    return error.InvalidCommand;

                return .{ .MAIL = try Path.parse(buffer[start + (.{ 'F', 'R', 'O', 'M', ':', '<' }).len .. buffer.len - 1]) };
            },
            // RCPT <SP> TO:<forward-path> <CRLF>
            .RCPT => {
                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Shortest valid reverse-path is:
                // "<" <c> "@" "#" <number> ">"
                if (buffer.len < (.{ 'M', 'A', 'I', 'L', ' ', 'T', 'O', ':', '<', 'a', '@', '#', '0', '>' }).len)
                    return error.InvalidCommand;

                // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
                // Must have at least on space!
                if (buffer[4] != ' ')
                    return error.NoSeperator;

                const start: usize = init: {
                    for (buffer[5..], 5..) |c, i| {
                        switch (c) {
                            ' ' => {},
                            else => break :init i,
                        }
                    }

                    return error.InvalidCommand;
                };

                if (buffer.len < start + (.{ 'T', 'O', ':', '<', 'a', '@', '#', '0', '>' }).len)
                    // Missing rest of the command.
                    return error.InvalidCommand;

                if (!std.ascii.eqlIgnoreCase(
                    buffer[start .. start + (.{ 'T', 'O', ':', '<' }).len],
                    &.{ 'T', 'O', ':', '<' },
                ) and
                    buffer[buffer.len - 1] != '>')
                    return error.InvalidCommand;

                return .{ .RCPT = try Path.parse(buffer[start + (.{ 'T', 'O', ':', '<' }).len .. buffer.len - 1]) };
            },
            // DATA <CRLF>
            .DATA => {
                if (buffer.len != (.{ 'D', 'A', 'T', 'A' }).len)
                    return error.InvalidCommand;

                return .{ .DATA = {} };
            },
            // QUIT <CRLF>
            .QUIT => {
                if (buffer.len != (.{ 'Q', 'U', 'I', 'T' }).len)
                    return error.InvalidCommand;

                return .{ .QUIT = {} };
            },
        }
    }
};

test "Valid commands" {
    try std.testing.expectEqual(CommandType.HELO, try CommandType.parse("HELO".*));
    try std.testing.expectEqual(CommandType.MAIL, try CommandType.parse("MAIL".*));
    try std.testing.expectEqual(CommandType.RCPT, try CommandType.parse("RCPT".*));
    try std.testing.expectEqual(CommandType.DATA, try CommandType.parse("DATA".*));
    try std.testing.expectEqual(CommandType.QUIT, try CommandType.parse("QUIT".*));
}

test "Invalid commands" {
    try std.testing.expectError(error.InvalidCommand, CommandType.parse("SOME".*));
    try std.testing.expectError(error.InvalidCommand, CommandType.parse("BURG".*));
    try std.testing.expectError(error.InvalidCommand, CommandType.parse("HDFD".*));
}

test "Case insensitive of commands" {
    try std.testing.expectEqual(CommandType.HELO, try CommandType.parse("heLo".*));
    try std.testing.expectEqual(CommandType.HELO, try CommandType.parse("hELo".*));
    try std.testing.expectEqual(CommandType.HELO, try CommandType.parse("Helo".*));
    try std.testing.expectEqual(CommandType.HELO, try CommandType.parse("hElO".*));
}

test "Valid command parsing" {
    try std.testing.expectEqual(
        Command{ .HELO = .{ .buffer = ("example.com" ++ @as([53]u8, @splat(0))).*, .len = 11 } },
        try Command.parse("HELO example.com\r\n"),
    );

    try std.testing.expectEqual(
        Command{ .MAIL = .{ .domain = .{
            .buffer = ("example.com" ++ @as([53]u8, @splat(0))).*,
            .len = 11,
        }, .user = .{
            .buffer = ("sender" ++ @as([58]u8, @splat(0))).*,
            .len = 6,
        } } },

        try Command.parse("MAIL FROM:<sender@example.com>\r\n"),
    );

    try std.testing.expectEqual(
        Command{ .RCPT = .{ .domain = .{
            .buffer = ("example.com" ++ @as([53]u8, @splat(0))).*,
            .len = 11,
        }, .user = .{
            .buffer = ("recipient" ++ @as([55]u8, @splat(0))).*,
            .len = 9,
        } } },

        try Command.parse("RCPT TO:<recipient@example.com>\r\n"),
    );

    try std.testing.expectEqual(Command{ .DATA = {} }, try Command.parse("DATA\r\n"));
    try std.testing.expectEqual(Command{ .QUIT = {} }, try Command.parse("QUIT\r\n"));
}
