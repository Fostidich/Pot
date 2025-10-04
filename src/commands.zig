const std = @import("std");
const print = std.debug.print;

const files = @import("files.zig");
const processes = @import("processes.zig");
const actives = @import("actives.zig");

pub fn addProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try files.getScriptFilePath(allocator, name);
    defer allocator.free(file_path);

    // try running nvim, nano otherwise
    var success = try processes.openEditor(allocator, "nvim", file_path);
    if (!success) {
        success = try processes.openEditor(allocator, "nano", file_path);
    }

    // log editor execution result
    if (success) {
        print("Editor closed correctly\n", .{});
    } else {
        print("Command may not have been saved\n", .{});
    }
}

pub fn deleteProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try files.getScriptFilePath(allocator, name);
    defer allocator.free(file_path);

    // delete file
    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        error.FileNotFound => {
            print("{s} not found\n", .{name});
            return;
        },
        else => return err,
    };
    print("{s} deleted\n", .{name});
}

pub fn listPrograms() !void {
    const allocator = std.heap.page_allocator;

    // retrieve dir data
    var dir = try std.fs.cwd().openDir(files.scripts_dir, .{ .iterate = true });
    defer dir.close();

    // build list with entries
    var entries = try std.ArrayList(std.fs.Dir.Entry).initCapacity(allocator, 16);
    defer entries.deinit(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        try entries.append(allocator, entry);
    }

    // sort by filename
    std.mem.sort(std.fs.Dir.Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: std.fs.Dir.Entry, b: std.fs.Dir.Entry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    // match active ones
    var active_procs = try actives.getActivePrograms(allocator);
    defer active_procs.deinit();

    // print entries if normal file
    for (entries.items) |entry| {
        if (entry.kind == .file and entry.name[0] != '.') {
            if (active_procs.get(entry.name)) |pid| {
                print("active: {s} ({})\n", .{ entry.name, pid });
            } else {
                print("        {s}\n", .{entry.name});
            }
        }
    }
}

pub fn startProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // get script file
    const script_path = try files.getScriptFilePath(allocator, name);
    defer allocator.free(script_path);
    const file_exists = try files.checkFileExists(script_path);
    if (!file_exists) {
        print("{s} not found\n", .{name});
        return;
    }

    // check not already active
    var active_procs = try actives.getActivePrograms(allocator);
    defer active_procs.deinit();
    if (active_procs.get(name)) |pid| {
        print("{s} already active ({})\n", .{ name, pid });
        return;
    }

    // fork and start process
    const pid = try processes.spawnDetached(allocator, script_path);

    // return if child, store pid if parent
    if (pid == 0) {
        return;
    } else {
        print("{s} started\n", .{name});
        try actives.addProgramToActives(allocator, name, pid);
    }
}

pub fn stopProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // get process pid if active
    var active_procs = try actives.getActivePrograms(allocator);
    defer active_procs.deinit();
    const pid = active_procs.get(name) orelse {
        print("{s} not active\n", .{name});
        return;
    };

    // kill process session
    if (try processes.killProcess(-pid)) {
        print("{s} stopped\n", .{name});
    } else {
        print("{s} not running\n", .{name});
    }

    // remove from the active files
    _ = active_procs.remove(name);
    try actives.overrideActivePrograms(allocator, active_procs);
}
