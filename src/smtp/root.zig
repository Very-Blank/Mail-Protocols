pub const Client = @import("client.zig");
pub const Server = @import("server.zig");
pub const Domain = @import("domain.zig");
pub const User = @import("user.zig");
pub const Path = @import("path.zig");

test "All for one!" {
    _ = @import("client.zig");
    _ = @import("server.zig");
    _ = @import("command.zig");
}
