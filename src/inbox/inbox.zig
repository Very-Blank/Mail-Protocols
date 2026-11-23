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
                    std.debug.print("Init failed got error {any}. diagnostics: {any}", .{ err, diags });
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
                std.debug.print("Init failed got error {any}. diagnostics: {any}", .{ err, diags });
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
        \\CREATE TABLE IF NOT EXISTS messages(
        \\  id INTEGER PRIMARY KEY, 
        \\  receiver INTEGER NOT NULL, 
        \\  sender TEXT NOT NULL UNIQUE,
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

pub fn insertUser(self: *Self, user: User) !void {
    var diags = sqlite.Diagnostics{};

    const query =
        \\INSERT INTO users(name) VALUES(?);
    ;

    var stmt = self.db.prepareWithDiags(query, .{ .diags = &diags }) catch |err| {
        std.debug.print("unable to prepare statement, got error {any}. diagnostics: {s}\n", .{ err, diags.err.?.message });
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

    var stmt = try self.db.prepare(query);
    defer stmt.deinit();

    return (try stmt.one(
        usize,
        .{},
        .{ .name = user.get() },
    ) orelse return error.UserNotFound);
}

pub fn insertMessage(self: *Self, receiver: usize, message: []const u8) !void {
    _ = receiver;
    _ = message;

    const query =
        \\INSERT INTO messages(receiver, sender, data) VALUES(?, ?, ?)
    ;

    var stmt = try self.db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .name = "José",
        .age = 40,
        .salary = 20000,
    });
}

test "Query user ID" {
    // const io = std.testing.io;
    // const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    const test_user: User = .init("test");
    var inbox: Self = try .init(.{ .file = null });
    defer inbox.deinit();
    try inbox.insertUser(test_user);

    try std.testing.expectEqual(1, try inbox.queryUserID(test_user));
}
