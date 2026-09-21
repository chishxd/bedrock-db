const std = @import("std");
const main = @import("main.zig");

/// IndexEntry stores information related to value
/// This allows us to seek to value directly instead of jst storing
/// offset to header then gotta read header, read value and key...
const IndexEntry = struct {
    value_offset: u64,
    value_len: u32,
};

///The real app state, holds everything important like DB file handle,
///arena allocator, index hashmap, and Io context
pub const BedrockDB = struct {
    file: std.Io.File,
    arena: std.heap.ArenaAllocator,
    index: std.StringHashMapUnmanaged(IndexEntry),
    io: std.Io,
    path: []const u8,
    ///Initializes Database with provided I/O context and db file path
    ///
    ///The `io` is used to create and read file
    ///`path` is path to file database, opens if it already exists, or creates
    ///if it doesn't exist
    ///
    ///Returns BedrockDB struct with file handle, index hashmap, allocator for
    ///hashmap, and I/O context
    ///
    ///Errors:
    /// File.OpenError if there is any issue to create/open file
    /// ReadFailed if file opens but fails to read for some reason
    /// InvalidHeader if the file the header does not contain MAGIC bytes
    pub fn init(io: std.Io, path: []const u8) !BedrockDB {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = false,
            .read = true,
        });

        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        const path_copy = try arena.allocator().dupe(u8, path);

        var db = BedrockDB{
            .file = file,
            .arena = arena,
            .index = .{},
            .io = io,
            .path = path_copy,
        };

        try db.buildIndex();

        return db;
    }

    fn writeRecord(writer: anytype, key: []const u8, value: []const u8) !void {
        var header = main.Header{
            .magic = main.MAGIC,
            .key_len = @intCast(key.len),
            .value_len = @intCast(value.len),
        };

        try writer.writeAll(std.mem.asBytes(&header));
        try writer.writeAll(key);
        try writer.writeAll(value);
    }
    pub fn buildIndex(self: *BedrockDB) !void {
        var read_buf: [1024]u8 = undefined;
        var file_reader = self.file.reader(self.io, &read_buf);

        var current_offset: u64 = 0;
        while (true) {
            var header: main.Header = undefined;
            file_reader.interface.readSliceAll(std.mem.asBytes(&header)) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };

            if (!std.mem.eql(u8, &header.magic, &main.MAGIC)) {
                return error.InvalidHeader;
            }

            var key_buf: [256]u8 = undefined;
            const key_slice = key_buf[0..header.key_len];
            try file_reader.interface.readSliceAll(key_slice);

            //Check if the value is a deleted value, I read that it is also called a "tombstone"
            //And yeah let's call it that
            if (header.value_len == 0) {
                _ = self.index.remove(key_slice);
                current_offset += @sizeOf(main.Header) + header.key_len;
                continue;
            }

            const index_entry = IndexEntry{
                .value_offset = current_offset + @sizeOf(main.Header) + header.key_len,
                .value_len = header.value_len,
            };

            var allocator = self.arena.allocator();
            const key_copy = try allocator.dupe(u8, key_slice);

            try self.index.put(allocator, key_copy, index_entry);

            current_offset += @sizeOf(main.Header) + header.key_len + header.value_len;

            _ = try file_reader.interface.discard(.limited(header.value_len));
        }
    }

    /// Deinitializes resources used up by application
    pub fn deinit(self: *BedrockDB) void {
        self.file.close(self.io);
        self.arena.deinit();
    }

    /// Writes Key, Value pair to file and updates the index HashMap with a new IndexEntry
    ///
    /// # Arguments:
    /// * `key` ([]const u8) : String value of a key to store
    /// * `value` ([]const u8) : String value of a value to store
    ///
    /// # Returns:
    /// It returns nothing on success, but error on failure.
    pub fn set(self: *BedrockDB, key: []const u8, value: []const u8) !void {
        const record_offset = try self.file.length(self.io);
        const val_offset = record_offset + @sizeOf(main.Header) + key.len;

        //Initializing buffer to write into the file
        var buffer: [1024]u8 = undefined;
        var file_writer = self.file.writer(self.io, &buffer);
        try file_writer.seekTo(record_offset);

        try writeRecord(&file_writer.interface, key, value);

        try file_writer.flush();

        const index_entry = IndexEntry{
            .value_len = @intCast(value.len),
            .value_offset = @intCast(val_offset),
        };

        var allocator = self.arena.allocator();
        const key_copy = try allocator.dupe(u8, key);

        try self.index.put(self.arena.allocator(), key_copy, index_entry);
    }

    /// Returns the latest value stored with the key or null
    ///
    /// key ([]const u8) : String value to fetch value for
    ///
    /// # Returns:
    /// 1. String key ([]u8) if key is present
    /// 2. Null if key is not present
    /// 3. Error on errors, I don't throw any errors, all of them are propagated
    /// and will be printed, ig
    pub fn get(self: *BedrockDB, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        const entry = self.index.get(key) orelse return null;

        var read_buf: [1024]u8 = undefined;
        var file_reader = self.file.reader(self.io, &read_buf);

        try file_reader.seekTo(entry.value_offset);

        const val_buf = try allocator.alloc(u8, entry.value_len);

        try file_reader.interface.readSliceAll(val_buf);

        return val_buf;
    }

    ///Delete specified key from the index and place a tombstone in Database
    pub fn delete(self: *BedrockDB, key: []const u8) !void {
        const record_offset = try self.file.length(self.io);

        //Initializing buffer to write into the file
        var buffer: [1024]u8 = undefined;
        var file_writer = self.file.writer(self.io, &buffer);

        try file_writer.seekTo(record_offset);

        try writeRecord(&file_writer.interface, key, "");
        try file_writer.flush();

        _ = self.index.remove(key);
    }

    pub fn compact(self: *BedrockDB) !void {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.createFile(self.io, "data.db.compact", .{});

        var write_buf: [1024]u8 = undefined;
        var file_writer = file.writer(self.io, &write_buf);

        var it = self.index.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;

            var read_buf: [1024]u8 = undefined;
            var file_reader = self.file.reader(self.io, &read_buf);

            try file_reader.seekTo(entry.value_ptr.value_offset);

            var val_buf: [1024]u8 = undefined;
            const val_slice = val_buf[0..entry.value_ptr.value_len];
            try file_reader.interface.readSliceAll(val_slice);

            try writeRecord(&file_writer.interface, key, val_slice);
            try file_writer.flush();
        }

        file.close(self.io);
        self.file.close(self.io);
        try cwd.rename("data.db.compact", cwd, self.path, self.io);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const saved_path = path_buf[0..self.path.len];
        @memcpy(saved_path, self.path);

        _ = self.arena.reset(.retain_capacity);
        self.index = .{};
        self.path = try self.arena.allocator().dupe(u8, saved_path);

        self.file = try cwd.createFile(self.io, self.path, .{ .truncate = false, .read = true });
        try self.buildIndex();
    }
};

test "test init boots on clean file" {
    var db = try BedrockDB.init(std.testing.io, "demo_db.db");

    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, "demo_db.db") catch {};

    try std.testing.expectEqual(0, db.index.count());
}

test "set writes record to disk" {
    const io = std.testing.io;

    var db = try BedrockDB.init(io, "test_set.db");
    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(io, "test_set.db") catch {};
    try db.set("hello", "world");

    const file_length = try db.file.length(io);
    try std.testing.expectEqual(@as(u64, 22), file_length);
    try std.testing.expectEqual(@as(u32, 1), db.index.size);
}
test "get reads record from disk" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var db = try BedrockDB.init(io, "test_set.db");
    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(io, "test_set.db") catch {};
    try db.set("hello", "world");
    try db.set("hero", "singham");
    try db.set("bhondu", "yash");
    try db.set("hero", "spidy");

    const result_bhondu = try db.get("bhondu", allocator);
    const result_hero = try db.get("hero", allocator);
    if (result_hero) |val| {
        defer std.testing.allocator.free(val);
        try std.testing.expectEqualStrings("spidy", val);
    }

    if (result_bhondu) |val| {
        defer std.testing.allocator.free(val);
        try std.testing.expectEqualStrings("yash", val);
    }
}

test "get returns null if no record found" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var db = try BedrockDB.init(io, "test_set.db");
    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(io, "test_set.db") catch {};
    try db.set("hello", "world");
    try db.set("hero", "singham");
    try db.set("bhondu", "yash");
    try db.set("hero", "spidy");

    const is_null = try db.get("villain", allocator);
    if (is_null) |val| {
        defer std.testing.allocator.free(val);
        try std.testing.expectEqual(null, val);
    }
}

test "delete persists across reboot" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var db1 = try BedrockDB.init(io, "test_del.db");
    defer std.Io.Dir.cwd().deleteFile(io, "test_del.db") catch {};

    try db1.set("hero", "spidy");
    try db1.set("rival", "quanti");
    try db1.delete("hero");
    db1.deinit(); //Power off the DB

    var db2 = try BedrockDB.init(io, "test_del.db");
    const hero = try db2.get("hero", allocator);
    try std.testing.expect(hero == null);

    const rival = try db2.get("rival", allocator);
    if (rival) |r| {
        defer allocator.free(r);
        try std.testing.expectEqualStrings("quanti", r);
    }
}

test "compaction shrinks file and preserves active keys" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var db = try BedrockDB.init(io, "test_compact.db");
    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(io, "test_compact.db") catch {};

    try db.set("hero", "goku");
    try db.set("hero", "spidy");
    try db.set("hero", "Iron Man");
    try db.set("place", "earth");
    try db.delete("place");

    const bloated_size = try db.file.length(io);

    try db.compact();

    const compact_size = try db.file.length(io);

    try std.testing.expect(compact_size < bloated_size);

    const hero = try db.get("hero", allocator);
    if (hero) |h| {
        defer allocator.free(h);
        try std.testing.expectEqualStrings("Iron Man", h);
    }

    const rival = try db.get("rival", allocator);
    try std.testing.expect(rival == null);
}
