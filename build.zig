const std = @import("std");
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const sqlite_root_path = std.fs.path.dirname(pkgs.sqlite.source.path).?;
    const sqlite_include_path = b.pathJoin(&.{ sqlite_root_path, "c" });
    const sqlite_src = b.pathJoin(&.{ sqlite_root_path, "c", "sqlite3.c" });

    const sqlite_lib = b.addStaticLibrary("sqlite", null);
    sqlite_lib.addCSourceFile(sqlite_src, &[_][]const u8{"-std=c99"});
    sqlite_lib.linkLibC();
    sqlite_lib.setTarget(target);
    sqlite_lib.setBuildMode(mode);

    const server = b.addExecutable("nochfragen", "backend/main.zig");
    server.setTarget(target);
    server.setBuildMode(mode);
    server.use_stage1 = true;
    pkgs.addAllTo(server);
    server.install();

    server.addIncludePath(sqlite_include_path);
    server.linkLibC();
    server.linkLibrary(sqlite_lib);

    const run_cmd = server.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const ctl = b.addExecutable("nochfragenctl", "backend/ctl.zig");
    ctl.setTarget(target);
    ctl.setBuildMode(mode);
    ctl.use_stage1 = true;
    pkgs.addAllTo(ctl);
    ctl.install();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
