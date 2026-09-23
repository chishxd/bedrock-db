const std = @import("std");
const BedrockDB = @import("db.zig").BedrockDB;

pub const MAGIC: [4]u8 = "BDRK".*;

/// Fixed-sized Header to Identify DB data from blob
/// No checksum in header so bit-corruption can't be detected
pub const Header = extern struct {
    ///Identifier to know about Struct
    magic: [4]u8,
    /// Length of the key in DB
    key_len: u32,
    /// Length of value in DB
    value_len: u32,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        std.debug.print(
            \\Usage:
            \\  bedrock-db set <key> <value>
            \\  bedrock-db get <key>
            \\  bedrock-db del <key>
            \\  bedrock-db compact
        , .{});
        return;
    }
    var db = try BedrockDB.init(io, "data-prod.db");
    defer db.deinit();

    const command = args[1];
    if (std.mem.eql(u8, command, "set")) {
        if (args.len < 4) {
            std.debug.print("Error: 'set' requires <key> and <value>\n", .{});
            return;
        }

        try db.set(args[2], args[3]);
        std.debug.print("[OK] Stored '{s}' = '{s}'\n", .{ args[2], args[3] });
    } else if (std.mem.eql(u8, command, "get")) {
        if (args.len < 3) {
            std.debug.print("Error: 'get' requires <key>\n", .{});
            return;
        }
        const val = try db.get(args[2], allocator);

        if (val) |v| {
            std.debug.print("[FOUND] {s} = {s}\n", .{ args[2], v });
        } else {
            std.debug.print("[NOT FOUND] Key '{s}' does not exist\n", .{args[2]});
        }
    } else if (std.mem.eql(u8, command, "del")) {
        if (args.len < 3) {
            std.debug.print("Error: 'del' requires <key>\n", .{});
            return;
        }
        try db.delete(args[2]);
        std.debug.print("[DELETED] Key '{s}' removed\n", .{args[2]});
    } else if (std.mem.eql(u8, command, "compact")) {
        try db.compact();
        std.debug.print("[OK] Database compacted successfully\n", .{});
    } else {
        std.debug.print("Unknown command: '{s}'. Use 'set' or 'get'.\n", .{command});
    }
}

test "Integration: Test full database lifecycle" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var db1 = try BedrockDB.init(io, "test_db.db");

    try db1.set("editor", "nvim");
    try db1.set("bhondu", "yash");
    try db1.set("goat", "quanti");
    try db1.set("hero", "spidy");
    try db1.set("villain", "venom");

    try db1.set("villain", "doc ock");
    try db1.set("hero", "deadpool");

    try db1.delete("editor");

    db1.deinit();

    var db2 = try BedrockDB.init(io, "test_db.db");
    defer std.Io.Dir.cwd().deleteFile(io, "test_db.db") catch {};
    defer db2.deinit();

    const editor = try db2.get("editor", allocator);
    try std.testing.expectEqual(null, editor);

    const bhondu = try db2.get("bhondu", allocator);
    if (bhondu) |val| {
        defer allocator.free(val);
        try std.testing.expectEqualStrings("yash", val);
    }

    const goat = try db2.get("goat", allocator);
    if (goat) |val| {
        defer allocator.free(val);
        try std.testing.expectEqualStrings("quanti", val);
    }

    const hero = try db2.get("hero", allocator);
    if (hero) |val| {
        defer allocator.free(val);
        try std.testing.expectEqualStrings("deadpool", val);
    }

    const villain = try db2.get("villain", allocator);
    if (villain) |val| {
        defer allocator.free(val);
        try std.testing.expectEqualStrings("doc ock", val);
    }
}
