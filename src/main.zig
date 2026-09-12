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

///set functions stores the binary payload passed with key and value with a Header to identify the value
fn set(io: std.Io, key: []const u8, value: []const u8) !void {
    const header = Header{ .magic = MAGIC, .key_len = @intCast(key.len), .value_len = @intCast(value.len) };

    const file = try std.Io.Dir.cwd().createFile(io, "test_db.db", .{ .truncate = false });
    defer file.close(io);

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

pub fn main(init: std.process.Init) !void {
    const key: []const u8 = "user";
    const value: []const u8 = "goku";

    const io = init.io;

    try set(io, key, value);
    std.debug.print("Successfully Stored key-value in Database\n", .{});
}
