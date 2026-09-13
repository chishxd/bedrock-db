const std = @import("std");

const MAGIC: [4]u8 = "BDRK".*;

/// Fixed-sized Header to Identify DB data from blob
const Header = extern struct {
    ///Identifier to know about Struct
    magic: [4]u8,
    /// Length of the key in DB
    key_len: u32,
    /// Length of value in DB
    value_len: u32,
};

///set functions stores the binary payload passed with key and value with a Header to identify the value
fn set(io: std.Io, file: std.Io.File, key: []const u8, value: []const u8) !void {
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

fn get(io: std.Io, file: std.Io.File, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    var read_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);

    try file_reader.seekTo(0);

    while (true) {
        var header: Header = undefined;
        try file_reader.interface.readSliceAll(std.mem.asBytes(&header));

        if (header.magic != MAGIC) {
            return error.InvalidHeader;
        }

        var key_buf: [256]u8 = undefined;
        const key_slice = key_buf[0..header.key_len];
        try file_reader.interface.readSliceAll(key_slice);

        if (std.mem.eql(u8, key, key_slice)) {
            const value_buf = try allocator.alloc(u8, header.value_len);
            try file_reader.interface.readSliceAll(value_buf);
            return value_buf;
        } else {
            try file_reader.seekTo(header.value_len);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const key: []const u8 = "user";
    const value: []const u8 = "goku";

    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "test_db.db", .{ .truncate = false, .read = true });
    defer file.close(io);

    try set(io, file, key, value);
    std.debug.print("Successfully Stored key-value in Database\n", .{});
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
