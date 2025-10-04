const std = @import("std");

const files = @import("files.zig");

const ActiveWithId = struct { pid: i32, name: []const u8 };

pub fn getActivePrograms(allocator: std.mem.Allocator) !std.StringHashMap(i32) {
    // prepare resulting content buffer
    var result = std.StringHashMap(i32).init(allocator);

    // open file
    const file = std.fs.cwd().openFile(files.active_file, .{}) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    defer file.close();

    // prepare temp buffer and file reader
    var buf: [1024]u8 = undefined;
    var reader = file.reader(&buf);
    const r = &reader.interface;

    // read line by line until end of file
    while (true) {
        // get line string
        const line = r.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        // parse and append to result
        const entry = parseActiveLine(line) catch continue;
        const key = try allocator.dupe(u8, entry.name);
        const value = entry.pid;
        try result.put(key, value);
    }

    // return owned
    return result;
}

pub fn addProgramToActives(allocator: std.mem.Allocator, name: []const u8, pid: i32) !void {
    // open file for appending
    var file = std.fs.cwd().openFile(files.active_file, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(files.active_file, .{}),
        else => return err,
    };
    defer file.close();

    // get string version of pid
    const pid_str = try std.fmt.allocPrint(allocator, "{}", .{pid});
    defer allocator.free(pid_str);

    // build line to append
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 8);
    defer buffer.deinit(allocator);
    try buffer.appendSlice(allocator, pid_str);
    try buffer.appendSlice(allocator, " ");
    try buffer.appendSlice(allocator, name);
    try buffer.appendSlice(allocator, "\n");
    const line = try buffer.toOwnedSlice(allocator);
    defer allocator.free(line);

    // append to file
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);
    try writer.seekTo(try writer.file.getEndPos());
    const w = &writer.interface;
    try w.print("{s}", .{line});
    try w.flush();
}

pub fn overrideActivePrograms(allocator: std.mem.Allocator, active_procs: std.StringHashMap(i32)) !void {
    // open file for overriding
    var file = try std.fs.cwd().openFile(files.active_file, .{ .mode = .read_write });
    defer file.close();
    try file.setEndPos(0);

    // prepare buffer
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 8);
    defer buffer.deinit(allocator);

    // prepare writer
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);
    const w = &writer.interface;

    // iterate over each entry for appending them
    var it = active_procs.iterator();
    while (it.next()) |entry| {
        // empty line buffer
        buffer.clearRetainingCapacity();

        // get string version of pid
        const pid_str = try std.fmt.allocPrint(allocator, "{}", .{entry.value_ptr.*});
        defer allocator.free(pid_str);

        // create line to append
        try buffer.appendSlice(allocator, pid_str);
        try buffer.appendSlice(allocator, " ");
        try buffer.appendSlice(allocator, entry.key_ptr.*);
        try buffer.appendSlice(allocator, "\n");
        const line = try buffer.toOwnedSlice(allocator);
        defer allocator.free(line);

        // append line
        try w.print("{s}", .{line});
    }

    // flush buffer
    try w.flush();
}

fn parseActiveLine(line: []const u8) !ActiveWithId {
    // parse pid and process name
    const first_space = std.mem.indexOfScalar(u8, line, ' ') orelse {
        return error.ActiveProcessParsingFailure;
    };
    const pid_str = line[0..first_space];
    const pid = try std.fmt.parseInt(i32, pid_str, 10);
    const name = line[first_space + 1 ..];

    // build and return entry
    return ActiveWithId{ .pid = pid, .name = name };
}
