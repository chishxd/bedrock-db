const std = @import("std");

const MAGIC: [4]u8 = "BDRK".*;

/// Fixed-sized Header to Identify DB data from blob
const Header = struct {
    ///Identifier to know about Struct
    magic: [4]u8,
    /// Length of the key in DB
    key_len: u16,
    /// Length of value in DB
    value_len: u32,
};

pub fn main(init: std.process.Init) !void {
    const key: []const u8 = "user";
    const value: []const u8 = "goku";

    const io = init.io;

    const header = Header{ .magic = MAGIC, .key_len = @intCast(key.len), .value_len = @intCast(value.len) };

    const file = try std.Io.Dir.cwd().createFile(io, "test_db.db", .{});
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);

    var writer = &file_writer.interface;

    try writer.writeAll(std.mem.asBytes(&header));
    try writer.writeAll(key);
    try writer.writeAll(value);

    try file_writer.flush();

    std.debug.print("Size of header is: {d}\n", .{@sizeOf(Header)});
}
