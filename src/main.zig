const std = @import("std");

pub const MAGIC: [4]u8 = "BDRK".*;

/// Fixed-sized Header to Identify DB data from blob
pub const Header = extern struct {
    ///Identifier to know about Struct
    magic: [4]u8,
    /// Length of the key in DB
    key_len: u32,
    /// Length of value in DB
    value_len: u32,
};

///set functions stores the binary payload passed with key and value with a Header to identify the value
pub fn set(io: std.Io, file: std.Io.File, key: []const u8, value: []const u8) !void {
    const header = Header{ .magic = MAGIC, .key_len = @intCast(key.len), .value_len = @intCast(value.len) };
    //Initializing buffer to write into the file
    var buffer: [1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);

    //This line makes sure the code won't rewrite on the file and will be append-only
    try file_writer.seekTo(try file.length(io));

    try file_writer.interface.writeAll(std.mem.asBytes(&header));
    try file_writer.interface.writeAll(key);
    try file_writer.interface.writeAll(value);

    try file_writer.flush();
}

/// get function returns the value for the passed key as a string.
fn get(io: std.Io, file: std.Io.File, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    var read_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);

    try file_reader.seekTo(0);
    var latest_val: ?[]u8 = null;

    while (true) {
        var header: Header = undefined;
        file_reader.interface.readSliceAll(std.mem.asBytes(&header)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        if (!std.mem.eql(u8, &header.magic, &MAGIC)) {
            return error.InvalidHeader;
        }

        var key_buf: [256]u8 = undefined;
        const key_slice = key_buf[0..header.key_len];
        try file_reader.interface.readSliceAll(key_slice);

        if (std.mem.eql(u8, key, key_slice)) {
            if (latest_val) |old| allocator.free(old);
            const value_buf = try allocator.alloc(u8, header.value_len);

            try file_reader.interface.readSliceAll(value_buf);
            latest_val = value_buf;
        } else {
            _ = try file_reader.interface.discard(.limited(header.value_len));
        }
    }

    return latest_val;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        std.debug.print(
            \\Usage:
            \\  bedrock-db set <key> <value>
            \\  bedrock-db get <key>
            \\
        , .{});
        return;
    }
    const file = try std.Io.Dir.cwd().createFile(io, "data.db", .{ .truncate = false, .read = true });
    defer file.close(io);

    const command = args[1];
    if (std.mem.eql(u8, command, "set")) {
        if (args.len < 4) {
            std.debug.print("Error: 'set' requires <key> and <value>\n", .{});
            return;
        }

        try set(io, file, args[2], args[3]);
        std.debug.print("[OK] Stored '{s}' = '{s}'\n", .{ args[2], args[3] });
    } else if (std.mem.eql(u8, command, "get")) {
        if (args.len < 3) {
            std.debug.print("Error: 'get' requires <key>\n", .{});
            return;
        }
        const val = try get(io, file, args[2], allocator);

        if (val) |v| {
            std.debug.print("[FOUND] {s} = {s}\n", .{ args[2], v });
        } else {
            std.debug.print("[NOT FOUND] Key '{s}' does not exist\n", .{args[2]});
        }
    } else {
        std.debug.print("Unknown command: '{s}'. Use 'set' or 'get'.\n", .{command});
    }
}

test "set writes record to disk" {
    const io = std.testing.io;

    const file = try std.Io.Dir.cwd().createFile(io, "test_db.db", .{ .truncate = false });
    defer file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, "test_db.db") catch {};
    try set(io, file, "hello", "world");

    const file_len = try file.length(io);
    try std.testing.expectEqual(@as(u64, 22), file_len);
}

test "get reads record from disk" {
    const io = std.testing.io;

    const file = try std.Io.Dir.cwd().createFile(io, "test_get.db", .{ .truncate = false, .read = true });
    defer file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, "test_get.db") catch {};
    try set(io, file, "user", "chish");
    try set(io, file, "user", "chish1");

    const allocator = std.testing.allocator;
    const value_get = try get(io, file, "user", allocator);

    if (value_get) |s| {
        defer allocator.free(s);

        try std.testing.expectEqualStrings("chish1", s);
    } else {
        return error.ExpectedValueGotNull;
    }
}

test "returns null if no key found" {
    const io = std.testing.io;

    const file = try std.Io.Dir.cwd().createFile(io, "test_failed_get.db", .{ .truncate = false, .read = true });
    defer file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, "test_failed_get.db") catch {};
    try set(io, file, "user", "chish");
    try set(io, file, "user", "chish1");

    const allocator = std.testing.allocator;
    const value_get = try get(io, file, "hello", allocator);

    try std.testing.expectEqual(@as(?[]u8, null), value_get);
}
