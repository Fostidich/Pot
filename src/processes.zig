const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const files = @import("files.zig");

pub fn spawnDetached(allocator: std.mem.Allocator, path: []const u8) !i32 {
    // fork process and make the parent return
    const pid = try posix.fork();
    if (pid != 0) {
        // return session leader pid
        return pid;
    }

    // make process session leader
    _ = try posix.setsid();

    // detach from terminal
    const dev_null = try std.fs.cwd().openFile("/dev/null", .{ .mode = .read_write });
    defer dev_null.close();
    try posix.dup2(dev_null.handle, posix.STDIN_FILENO);
    try posix.dup2(dev_null.handle, posix.STDOUT_FILENO);
    try posix.dup2(dev_null.handle, posix.STDERR_FILENO);

    // start script command
    const shell_path = switch (builtin.os.tag) {
        .macos => "/bin/zsh",
        else => "/bin/bash",
    };
    const args = &[_][]const u8{
        shell_path,
        path,
    };
    var proc = std.process.Child.init(args, allocator);
    try proc.spawn();

    // should return 0 as child
    return pid;
}

pub fn killProcess(sess_id: i32) !bool {
    posix.kill(sess_id, 9) catch |err| switch (err) {
        error.ProcessNotFound => {
            return false;
        },
        else => return err,
    };
    return true;
}

pub fn openEditor(allocator: std.mem.Allocator, editor_name: []const u8, file_path: []const u8) !bool {
    // run editor command
    const editor_command = &[_][]const u8{ editor_name, file_path };
    var editor_process = std.process.Child.init(editor_command, allocator);
    try editor_process.spawn();

    // wait for it to finish
    const result = editor_process.wait() catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };

    // return exit success
    return switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };
}
