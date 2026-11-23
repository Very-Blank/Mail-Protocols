const std = @import("std");
const sqlite = @import("sqlite");
const smtp = @import("smtp");

const Db = sqlite.Db;
const User = smtp.User;
const Path = smtp.Path;

db: Db,

const Self = @This();

pub const Message = struct {
    data: []const u8,
    sender: []const u8,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.data = undefined;
        allocator.free(self.sender);
        self.sender = undefined;
    }
};

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
        \\  read TEXT NOT NULL DEFAULT 'UNREAD' CHECK (read in ('READ', 'UNREAD')),
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

pub fn addUser(self: *Self, user: User) !void {
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

pub fn addMessage(self: *Self, receiver: User, sender: Path, data: []const u8) !void {
    const query =
        \\INSERT INTO inbox(receiver, sender, data) VALUES((SELECT id FROM users WHERE name = ?), ?, ?);
    ;

    var diags = sqlite.Diagnostics{};
    var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
        logDiagnostics(err, diags);
        return err;
    };

    defer stmt.deinit();

    var buffer: [Path.max_len]u8 = @splat(0);
    const sender_formatted: []u8 = std.mem.print(&buffer, "{s}@{s}", .{ sender.user.get(), sender.domain.get() }) catch unreachable;

    try stmt.exec(.{}, .{
        .receiver = receiver.get(),
        .sender = sender_formatted,
        .data = data,
    });
}

pub fn getMessages(
    self: *Self,
    allocator: std.mem.Allocator,
    receiver: User,
) ![]Message {
    var diags = sqlite.Diagnostics{};

    const query =
        \\UPDATE inbox SET read = 'READ' WHERE receiver = (SELECT id FROM users WHERE name = ?) AND read = 'UNREAD' RETURNING data, sender;
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
            receiver.get(),
        },
    );
}

pub fn logDiagnostics(err: anyerror, diagnostics: sqlite.Diagnostics) void {
    var buffer: [512]u8 = @splat(0);
    var writer: std.Io.Writer = .fixed(&buffer);
    const fmt = std.json.fmt(diagnostics, .{ .whitespace = .indent_2, .escape_unicode = true });
    fmt.format(&writer) catch return;
    std.log.err("Got error {any}.\nDiagnostics:\n{s}\n", .{ err, buffer[0..writer.end] });
}

test "Add user" {
    // const io = std.testing.io;
    // const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    var inbox: Self = try .init(.{ .file = null });
    defer inbox.deinit();

    const test_user: User = .init("test");
    try inbox.addUser(test_user);

    // FIXME: add check where we query users and see that it's getting added.
}

test "Write a new message to user's inbox and read it." {
    // const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    var inbox: Self = try .init(.{ .file = null });
    defer inbox.deinit();

    const test_user: User = .init("test");
    try inbox.addUser(test_user);

    const message =
        \\Subject: Test message
        \\From: sender@example.com
        \\To: recipient@example.com
        \\
        \\Hello, this is a test.
    ;

    try inbox.addMessage(test_user, .init("sender", "example.com"), message);

    {
        const messages: []Message = try inbox.getMessages(allocator, test_user);
        defer {
            for (messages) |capture| {
                allocator.free(capture.data);
                allocator.free(capture.sender);
            }

            allocator.free(messages);
        }

        try std.testing.expectEqualDeep(@as([]const Message, &.{Message{ .data = message, .sender = "sender@example.com" }}), messages);
    }

    {
        const messages: []Message = try inbox.getMessages(allocator, test_user);
        try std.testing.expectEqualDeep(@as([]const Message, &.{}), messages);
    }
}
