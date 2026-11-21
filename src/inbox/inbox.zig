const std = @import("std");
const sqlite = @import("sqlite");

const Db = sqlite.Db;

db: Db,

const Self = @This();

pub fn init() !Self {
    return .{
        .db = try Db.init(.{
            .mode = Db.Mode{ .File = "./inbox.sqlite" },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .SingleThread,
        }),
    };
}

pub fn deinit(self: *Self) void {
    self.db.deinit();
}
