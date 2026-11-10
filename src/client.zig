const std = @import("std");
const linux = std.os.linux;

const command = @import("command.zig");
const Command = command.Command;
const CommandType = command.CommandType;

// https://www.rfc-editor.org/info/rfc821/#page-42
const max_command_len = 512;
const max_reply_len = 512;

// Specification says min max is 1000, but it doesn't count for the transparency periods.
// Example:
//..<CRLF>
//..<CRLF>
//..<CRLF>
//.<CRLF>
// Would have 12 characters, but by spec actually 15.
// We can use this function to see proportion of counted characters to all characters (worst case: all dots).
// f(x) = (x × (3) + (3)) / (x × (4) + (3))
// (lim x->inf = 3/4)
// At 1000 only ~ 0.75% counted.
// So to account for the whole we could do (1000 / 0.75) ~= 1333.33..
// But for safety will do (1000 / (2/3)) = 1500
const max_text_len = 1500;

// FIXME: Change localhost to the actuall domain
const domain = "localhost";

commad_line: [max_command_len]u8 = @splat(0),
reply_line: [max_reply_len]u8 = @splat(0),
text_line: [max_text_len]u8 = @splat(0),
socket: linux.fd_t,
details: linux.sockaddr.in,

const Self = @This();

pub fn deinit(self: *Self) void {
    _ = linux.shutdown(self.socket, linux.SHUT.RDWR);
    _ = linux.close(self.socket);
}

// Reply codes can be found here:
// https://www.rfc-editor.org/info/rfc821/#page-35
pub fn serve(self: *Self) !void {
    try self.reply("{d} {s} Service ready", .{ 220, domain });

    origin: switch (try self.readCommand()) {
        .HELO => |client_domain| switch (try self.readCommand()) {
            .MAIL => |reverse_path| {
                _ = client_domain;
                _ = reverse_path;

                mail: switch (try self.readCommand()) {
                    .RCPT => |forward_path| {
                        _ = forward_path;

                        continue :mail try self.readCommand();
                    },
                    .DATA => {
                        const length: usize = init: {
                            var buffer: []u8 = self.text_line[0..];
                            var length: usize = 0;

                            // FIXME: ADD MAX ITERATION COUNT
                            while (true) {
                                if (1400 <= length) {
                                    // FIXME: TOO MUCH DATA.
                                }

                                const result = linux.read(
                                    self.socket,
                                    buffer.ptr,
                                    buffer.len,
                                );

                                if (linux.errno(result) != .SUCCESS) {
                                    return error.FailedToRead;
                                }

                                // We do this because there is no way of knowing when the end sequence happens.
                                // FIXME: THIS ISN'T DONE!
                                if (std.mem.find(u8, &self.text_line, &.{ '\r', '\n', '.', '\r', '\n' })) |end| {
                                    break :init end;
                                }

                                length += result;
                                buffer = self.text_line[length..];
                            }
                        };

                        const data = init: {
                            var move: usize = 0;
                            var state: enum {
                                none,
                                @"\r",
                                @"\r\n",
                            } = .none;

                            var i: usize = 0;
                            while (i + move < length) {
                                switch (self.text_line[i]) {
                                    '\r' => state = .@"\r",
                                    '\n' => state = switch (state) {
                                        .@"\r" => .@"\r\n",
                                        else => .none,
                                    },
                                    '.' => {
                                        defer state = .none;

                                        switch (state) {
                                            .@"\r\n" => {
                                                move += 1;
                                                continue;
                                            },
                                            else => {},
                                        }
                                    },
                                    else => {},
                                }

                                self.text_line[i] = self.text_line[i + move];
                                i += 1;
                            }

                            break :init self.text_line[0 .. length - move];
                        };

                        std.debug.print("{s}", .{data});
                    },
                    else => {
                        try self.reply("{d} Bad sequence of commands", .{503});

                        continue :origin try self.readCommand();
                    },
                }
            },
            else => {
                try self.reply("{d} Bad sequence of commands", .{503});

                continue :origin try self.readCommand();
            },
        },
        .QUIT => {
            try self.reply("{d} {s} Service closing transmission channel", .{ 221, domain });
        },
        else => {
            try self.reply("{d} Bad sequence of commands", .{503});

            continue :origin try self.readCommand();
        },
    }
}

/// Writes the message to the socket, appends <CRLF> to the end.
pub fn reply(self: *Self, comptime format: []const u8, args: anytype) !void {
    const slice = std.mem.print(&self.reply_line, format ++ .{ '\r', '\n' }, args) catch unreachable;
    if (linux.errno(linux.write(self.socket, slice.ptr, slice.len)) != .SUCCESS)
        return error.WriteFailed;
}

pub fn readCommand(self: *Self) !Command {
    const input: []const u8 = init: {
        var buffer: []u8 = self.commad_line[0..];
        var length: usize = 0;

        // FIXME: MAX ITERATION COUNT
        // FIXME: IF BUFFER IS FULL AND NO END FOUND RETURN ERROR!
        while (true) {
            const result = linux.read(
                self.socket,
                buffer.ptr,
                buffer.len,
            );

            if (linux.errno(result) != .SUCCESS) {
                return error.FailedToRead;
            }

            if (std.mem.find(u8, &self.commad_line, &.{ '\r', '\n' })) |end|
                break :init self.commad_line[0 .. end + (.{ '\r', '\n' }).len];

            length += result;
            buffer = self.commad_line[length..];
        }
    };

    return Command.parse(input);
}
