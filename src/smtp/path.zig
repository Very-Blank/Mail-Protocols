const std = @import("std");
const User = @import("user.zig");
const Domain = @import("domain.zig");

user: User,
domain: Domain,

const Self = @This();

// https://www.rfc-editor.org/info/rfc821/#page-30
// We only implement a subset of the spec.
// FULL:
// <path> ::= "<" [ <a-d-l> ":" ] <mailbox> ">"
// IMPL:
// <path> ::= "<" <mailbox> ">"
//
// FULL:
// <local-part> ::= <dot-string> | <quoted-string>
// IMPL:
// <local-part> ::= <dot-string>
//
// FULL:
// <char> ::= <c> | "\" <x>
// IMPL:
// <char> ::= <a> | <d>
pub fn parse(buffer: []const u8) !Self {
    // https://www.rfc-editor.org/info/rfc821/#section-4.1.2
    // Shortest valid reverse-path is:
    // <c> "@" "#" <number>
    std.debug.assert((.{ 'a', '@', '#', '0' }).len <= buffer.len);

    const middle: usize = found: {
        var i: usize = buffer.len - 1;
        while (0 < i) : (i -= 1) {
            switch (buffer[i]) {
                '@' => break :found i,
                else => {},
            }
        }

        return error.NoPathMiddle;
    };

    if (middle == 0 or buffer.len < middle + (.{ '#', '0' }).len)
        return error.InvalidPath;

    return .{
        .user = try User.parse(buffer[0..middle]),
        .domain = try Domain.parse(buffer[middle + 1 ..]),
    };
}
