const std = @import("std");
const print = std.debug.print;

const local_dir = "~/.local/pot/";

pub fn addProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try getGeneralFilePath(allocator, name);
    defer allocator.free(file_path);

    // try running nvim, nano otherwise
    var success = try runProcess(allocator, "nvim", file_path);
    if (!success) {
        success = try runProcess(allocator, "nano", file_path);
    }

    // log editor execution result
    if (success) {
        print("Command stored correctly\n", .{});
    } else {
        print("Command may not have been saved\n", .{});
    }
}

pub fn deleteProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try getGeneralFilePath(allocator, name);
    defer allocator.free(file_path);

    // delete file
    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        error.FileNotFound => {
            print("{s} not found\n", .{name});
            return;
        },
        else => return err,
    };
    print("Deleted\n", .{});
}

pub fn listPrograms() !void {
    const allocator = std.heap.page_allocator;

    // retrieve programs path
    const path = try expandHomePath(allocator, local_dir);
    defer allocator.free(path);

    // retrieve dir data
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();

    // print entries if normal file
    while (try it.next()) |entry| {
        if (entry.kind == .file and entry.name[0] != '.') {
            print("{s}\n", .{entry.name});
        }
    }
}

pub fn getProgram(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // construct path string
    const file_path = try getGeneralFilePath(allocator, name);
    defer allocator.free(file_path);

    // open file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // prepare resulting content buffer
    var result = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer result.deinit(allocator);

    // prepare temp buffer and file reader
    var buf: [1024]u8 = undefined;
    var reader = file.reader(&buf);

    // read until end of file
    while (true) {
        const bytes_read = reader.read(buf[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        try result.appendSlice(allocator, buf[0..bytes_read]);
    }

    // return owned
    return result.toOwnedSlice(allocator);
}

pub inline fn createRequiredDir(allocator: std.mem.Allocator) !void {
    // create all parent directories
    const path = try expandHomePath(allocator, local_dir);
    defer allocator.free(path);
    try std.fs.cwd().makePath(path);
}

fn getGeneralFilePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // create var size buffer
    var path_buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer path_buffer.deinit(allocator);

    // append dir and filename
    try path_buffer.appendSlice(allocator, local_dir);
    try path_buffer.appendSlice(allocator, filename);

    // expand tilde
    return try expandHomePath(allocator, path_buffer.items);
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

fn runProcess(allocator: std.mem.Allocator, editor_name: []const u8, file_path: []const u8) !bool {
    // run editor command
    const editor_command = &[_][]const u8{ editor_name, file_path };
    var editor_process = std.process.Child.init(editor_command, allocator);
    try editor_process.spawn();

    // wait for it to finish
    const result = editor_process.wait() catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };

    // print exit result
    return switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };
}
