const std = @import("std");
const sqlite = @import("sqlite");
const smtp = @import("smtp");

const Db = sqlite.Db;
const User = smtp.User;

db: Db,

const Self = @This();

pub fn init() !Self {
    var self: Self = .{
        .db = try Db.init(.{
            .mode = Db.Mode{ .File = "./inbox.sqlite" },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .SingleThread,
        }),
    };

    errdefer self.deinit();

    // Name could be the primary key, but that isn't a good idea.
    try self.exec(
        \\CREATE TABLE IF NOT EXISTS users(
        \\  id INTEGER PRIMARY KEY, 
        \\  name TEXT NOT NULL UNIQUE,
        \\);
    , .{}, .{});

    try self.exec(
        \\CREATE TABLE IF NOT EXISTS messages(
        \\  id INTEGER PRIMARY KEY, 
        \\  receiver INTEGER NOT NULL, 
        \\  sender TEXT NOT NULL UNIQUE,
        \\  data TEXT NOT NULL,
        \\
        \\  FOREING KEY (receiver) REFERENCES user(id) ON DELETE CASCADE,
        \\);
    , .{}, .{});

    return self;
}

pub fn queryUserID(self: *Self, user: User) !usize {
    const query =
        \\SELECT id FROM users WHERE name = ?
    ;

    var stmt = try self.db.prepare(query);
    defer stmt.deinit();

    const row = try stmt.one(
        [16]u8,
        .{},
        .{ .name = user.get() },
    );

    if (row) |id| {
        std.log.debug("id: {s}", .{std.fmt.fmtSliceHexLower(&id)});
    }
}

pub fn insertMessage(self: *Self, receiver: usize, message: []const u8) !void {
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

pub fn deinit(self: *Self) void {
    self.db.deinit();
}
