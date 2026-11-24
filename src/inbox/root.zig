pub const Inbox = @import("inbox.zig");
pub const Server = @import("server.zig");
pub const Post = Server.Post;

test "All for one!" {
    _ = @import("server.zig");
    _ = @import("inbox.zig");
}
