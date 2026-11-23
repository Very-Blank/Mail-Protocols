const std = @import("std");
const sqlite = @import("sqlite");
const smtp = @import("smtp");

const Db = sqlite.Db;
const User = smtp.User;

db: Db,

const Self = @This();

pub fn init(options: struct { file: ?[:0]const u8 = "./inbox.sqlite" }) !Self {
    var diags = sqlite.Diagnostics{};

    var self: Self = init: {
        if (options.file) |file| {
            break :init .{
                .db = Db.init(.{
                    .mode = Db.Mode{ .File = file },
                    .diags = &diags,
                    .open_flags = .{
                        .write = true,
                        .create = true,
                    },
                    .threading_mode = .SingleThread,
                }) catch |err| {
                    logDiagnostics(err, diags);
                    return err;
                },
            };
        }

        break :init .{
            .db = Db.init(.{
                .mode = Db.Mode{ .Memory = {} },
                .diags = &diags,
                .open_flags = .{ .write = true },
                .threading_mode = .SingleThread,
            }) catch |err| {
                logDiagnostics(err, diags);
                return err;
            },
        };
    };

    errdefer self.deinit();

    // Name could be the primary key, but that isn't a good idea.
    try self.db.exec(
        \\CREATE TABLE IF NOT EXISTS users(
        \\  id INTEGER PRIMARY KEY, 
        \\  name TEXT NOT NULL UNIQUE
        \\);
    , .{}, .{});

    try self.db.exec(
        \\CREATE TABLE IF NOT EXISTS inbox(
        \\  id INTEGER PRIMARY KEY, 
        \\  receiver INTEGER NOT NULL, 
        \\  sender TEXT NOT NULL UNIQUE,
        \\  read TEXT NOT NULL DEFAULT "UNREAD",
        \\  data TEXT NOT NULL,
        \\
        \\  FOREIGN KEY (receiver) REFERENCES user(id) ON DELETE CASCADE
        \\);
    , .{}, .{});

    return self;
}

pub fn deinit(self: *Self) void {
    self.db.deinit();
}

pub fn insertIntoUser(self: *Self, user: User) !void {
    const query =
        \\INSERT INTO users(name) VALUES(?);
    ;

    var diags = sqlite.Diagnostics{};
    var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
        logDiagnostics(err, diags);
        return err;
    };

    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .name = user.get(),
    });
}

pub fn queryUserID(self: *Self, user: User) !usize {
    const query =
        \\SELECT id FROM users WHERE name = ?
    ;

    var diags = sqlite.Diagnostics{};
    var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
        logDiagnostics(err, diags);
        return err;
    };

    defer stmt.deinit();

    return (try stmt.one(
        usize,
        .{},
        .{ .name = user.get() },
    ) orelse return error.UserNotFound);
}

pub fn insertIntoInbox(self: *Self, receiver: usize, sender: []const u8, data: []const u8) !void {
    const query =
        \\INSERT INTO inbox(receiver, sender, data) VALUES(?, ?, ?)
    ;

    var diags = sqlite.Diagnostics{};
    var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
        logDiagnostics(err, diags);
        return err;
    };

    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .receiver = receiver,
        .sender = sender,
        .data = data,
    });
}

pub const Message = struct {
    data: []const u8,
    sender: []const u8,
};

pub fn queryInbox(
    self: *Self,
    allocator: std.mem.Allocator,
    receiver: usize,
    options: struct { state: enum { read, unread, all } = .all },
) ![]Message {
    var diags = sqlite.Diagnostics{};

    switch (options.state) {
        .all => {
            const query =
                \\SELECT data, sender FROM inbox WHERE id = ?
            ;

            var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
                logDiagnostics(err, diags);
                return err;
            };

            defer stmt.deinit();

            return try stmt.all(
                Message,
                allocator,
                .{},
                .{
                    .id = receiver,
                },
            );
        },
        else => |state| {
            const query =
                \\SELECT data, sender FROM inbox WHERE id = ? AND read = ?
            ;

            var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
                logDiagnostics(err, diags);
                return err;
            };

            defer stmt.deinit();

            return try stmt.all(
                Message,
                allocator,
                .{},
                .{
                    .id = receiver,
                    .read = switch (state) {
                        .read => "READ",
                        .unread => "UNREAD",
                        else => unreachable,
                    },
                },
            );
        },
    }
}

pub fn logDiagnostics(err: anyerror, diagnostics: sqlite.Diagnostics) void {
    var buffer: [512]u8 = @splat(0);
    var writer: std.Io.Writer = .fixed(&buffer);
    const fmt = std.json.fmt(diagnostics, .{ .whitespace = .indent_2, .escape_unicode = true });
    fmt.format(&writer) catch return;
    std.log.err("Got error {any}.\nDiagnostics:\n{s}\n", .{ err, buffer[0..writer.end] });
}

test "Add user and it's ID" {
    // const io = std.testing.io;
    // const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    var inbox: Self = try .init(.{ .file = null });
    defer inbox.deinit();

    const test_user: User = .init("test");
    try inbox.insertIntoUser(test_user);

    try std.testing.expectEqual(1, try inbox.queryUserID(test_user));
}

test "Write a new message to user's inbox" {
    // const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    var inbox: Self = try .init(.{ .file = null });
    defer inbox.deinit();

    const test_user: User = .init("test");
    try inbox.insertIntoUser(test_user);

    const user_id = try inbox.queryUserID(test_user);

    try inbox.insertIntoInbox(
        user_id,
        "sender@example.com",
        \\Subject: Test message\r
        \\From: sender@example.com\r
        \\To: recipient@example.com\r
        \\\r
        \\Hello, this is a test.\r
        ,
    );

    const messages: []Message = try inbox.queryInbox(allocator, user_id, .{});
    defer {
        for (messages) |message| {
            allocator.free(message.data);
            allocator.free(message.sender);
        }

        allocator.free(messages);
    }

    std.debug.print("{s}", .{messages[0].data});
}
