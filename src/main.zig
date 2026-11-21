const std = @import("std");

pub fn main(_: std.process.Init) !void {
    std.debug.print("Hello!\nThis is suppose to be a help message, but it's empty.\nPlease add something usefull here.", .{});
}
