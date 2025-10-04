const std = @import("std");

pub var scripts_dir: []const u8 = "";
pub var active_file: []const u8 = "";

pub fn init(allocator: std.mem.Allocator) !void {
    scripts_dir = try expandHomePath(allocator, "~/.local/pot/scripts/");
    active_file = try expandHomePath(allocator, "~/.local/pot/active");
}

pub fn getScriptFilePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // create var size buffer
    var path_buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer path_buffer.deinit(allocator);

    // append dir and filename
    try path_buffer.appendSlice(allocator, scripts_dir);
    try path_buffer.appendSlice(allocator, filename);

    // return owned
    return path_buffer.toOwnedSlice(allocator);
}

pub fn checkFileExists(path: []const u8) !bool {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();
    return true;
}

pub inline fn createRequiredDir() !void {
    // create all parent directories
    try std.fs.cwd().makePath(scripts_dir);
}

fn expandHomePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // check that there actually is a tilde to expand at the start
    if (path.len == 0 or path[0] != '~') {
        return error.NoHomeToExpand;
    }

    // get home env var
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    // construct path string
    var path_buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer path_buffer.deinit(allocator);
    try path_buffer.appendSlice(allocator, home_dir);
    try path_buffer.appendSlice(allocator, path[1..]);

    // return owned
    return path_buffer.toOwnedSlice(allocator);
}
