const std = @import("std");
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const server = b.addExecutable("nochfragen", "backend/main.zig");
    server.setTarget(target);
    server.setBuildMode(mode);
    server.use_stage1 = true;
    pkgs.addAllTo(server);
    server.install();

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
