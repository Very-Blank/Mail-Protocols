const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const impl = b.option(enum {
        help,
        smtp,
    }, "module", "Switch between the different implementations") orelse .help;

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const inbox_module = b.addModule("inbox", .{
        .root_source_file = b.path("src/inbox/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite.module("sqlite") },
        },
    });

    const smtp_module = b.addModule("smtp", .{
        .root_source_file = b.path("src/smtp/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "inbox", .module = inbox_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "email",
        .root_module = b.createModule(.{
            .root_source_file = switch (impl) {
                .help => b.path("src/main.zig"),
                .smtp => b.path("src/smtp/main.zig"),
            },
            .target = target,
            .optimize = optimize,
            .imports = switch (impl) {
                .help => &.{},
                .smtp => &.{
                    .{ .name = "smtp", .module = smtp_module },
                },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const test_step = b.step("test", "Run tests");

    inline for (.{ smtp_module, inbox_module }) |module| {
        const tests = b.addTest(.{
            .root_module = module,
        });

        const run_tests = b.addRunArtifact(tests);

        test_step.dependOn(&run_tests.step);
    }
}
