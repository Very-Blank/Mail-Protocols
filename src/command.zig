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
        std.debug.assert((.{ '\r', '\n' }).len <= raw.len);
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
                ) or
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
                ) or
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

test "Invalid command parsing" {
    try std.testing.expectError(error.NoSeperator, Command.parse("MAILFROM:<sender@example.com>\r\n"));
    try std.testing.expectError(error.NoSeperator, Command.parse("RCPTTO:<recipient@example.com>\r\n"));

    try std.testing.expectError(error.InvalidCommand, Command.parse("MAIL FROM:sender@example.com>\r\n"));
    try std.testing.expectError(error.InvalidCommand, Command.parse("RCPT TO:recipient@example.com>\r\n"));

    try std.testing.expectError(error.InvalidCommand, Command.parse("MAIL FROM:<sender@example.com\r\n"));
    try std.testing.expectError(error.InvalidCommand, Command.parse("RCPT TO:<recipient@example.com\r\n"));

    // try Command.parse("RCPT TO:<recipient@example.com>\r\n"),
}

fn mutate(smith: *std.testing.Smith, list: *std.ArrayList(u8)) void {
    const tokens = [_][]const u8{
        "\r\n",
        "\x00",
        "MAIL",
        "FROM",
        "RCPT",
        "TO",
        "\r",
        "\n",
        "<",
        ">",
        "@",
        ":",
        ".",
        " ",
    };

    const max_duplicate_len = 4;

    switch (smith.value(enum {
        delete,
        overwrite,
        byte,
        token,
        duplicate,
        truncate,
        swap,
    })) {
        .delete => if (0 < list.items.len) {
            _ = list.orderedRemove(smith.valueRangeLessThan(u64, 0, list.items.len));
        },
        .overwrite => if (0 < list.items.len) {
            list.items[smith.valueRangeLessThan(u64, 0, list.items.len)] = smith.value(u8);
        },
        .byte => if (list.items.len + 1 <= 510) {
            list.insertAssumeCapacity(smith.valueRangeAtMost(u64, 0, list.items.len), smith.value(u8));
        },
        .token => if (list.items.len + 4 <= 510) {
            const token = tokens[smith.valueRangeLessThan(u64, 0, tokens.len)];
            list.insertSliceAssumeCapacity(smith.valueRangeAtMost(u64, 0, list.items.len), token);
        },
        .duplicate => if (1 < list.items.len) {
            const start = smith.valueRangeLessThan(u64, 0, list.items.len - 1);
            const len = @min(smith.valueRangeAtMost(u64, 1, list.items.len - start), max_duplicate_len);

            const times = smith.valueRangeAtMost(u64, 0, @divFloor(510 - list.items.len, len));

            const slice = list.items[start .. start + len];
            for (0..times) |_| {
                list.insertSliceAssumeCapacity(start + len, slice);
            }
        },
        .truncate => if (1 < list.items.len) {
            list.shrinkRetainingCapacity(smith.valueRangeLessThan(u64, 1, list.items.len));
        },
        .swap => if (1 < list.items.len) {
            const a = smith.valueRangeLessThan(u64, 0, list.items.len);
            const b = smith.valueRangeLessThan(u64, 0, list.items.len);
            std.mem.swap(u8, &list.items[a], &list.items[b]);
        },
    }
}

fn fuzzParse(_: void, smith: *std.testing.Smith) anyerror!void {
    const seeds = [_][]const u8{
        "HELO a@#0",
        "HELO sender@example.com",
        "HELO example.com",
        "HELO mail.example.com",
        "HELO #1",
        "HELO [192.168.0.1]",
        "HELO a.#2.example.com",

        "MAIL FROM:<sender@example.com>",
        "MAIL FROM:<a@#1>",
        "MAIL FROM:<first.last@example.com>",
        "MAIL FROM:<user+tag@sub.example.com>",
        "MAIL FROM:<a!b#c$d%e&f'g*h=i?j^k_l`m{n|o}p~q@example.com>",
        "MAIL FROM:<user@[10.0.0.1]>",
        "MAIL FROM:<user@#4294967295>",
        "MAIL FROM:<\"quoted string\"@example.com>",
        "MAIL FROM:<\"a\\\"b\\\\c\"@example.com>",
        "MAIL FROM:<@relay.example.com:user@example.com>",
        "MAIL FROM:<@relay1.example.com,@relay2.example.org:user@example.com>",
        "mail from:<lowercase@example.com>",

        "RCPT TO:<recipient@example.com>",
        "RCPT TO:<a@#0>",
        "RCPT TO:<recipient@example.com>",
        "RCPT TO:<user@[127.0.0.1]>",
        "RCPT TO:<\"Mr. Smith\"@example.com>",
        "RCPT TO:<@hop.example.com,@hop2.example.net:dest@example.org>",
        "rcpt to:<lower@example.com>",

        "QUIT",

        "DATA",

        "",
    };

    var buffer: [512]u8 = @splat(0);
    var list: std.ArrayList(u8) = .initBuffer(&buffer);

    const seed = smith.valueRangeLessThan(u64, 0, seeds.len);
    list.appendSliceAssumeCapacity(seeds[seed]);

    for (0..smith.valueRangeAtMost(u64, 0, 100)) |_| mutate(smith, &list);

    list.appendSliceAssumeCapacity(&.{ '\r', '\n' });

    _ = Command.parse(list.items) catch return;
}

test "fuzz: Command.parse never panics" {
    try std.testing.fuzz({}, fuzzParse, .{});
}
