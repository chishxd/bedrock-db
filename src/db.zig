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
        var index: std.StringHashMapUnmanaged(IndexEntry) = .{};

        var read_buf: [1024]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);

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

            const index_entry = IndexEntry{
                .value_offset = current_offset + @sizeOf(main.Header) + header.key_len,
                .value_len = header.value_len,
            };

            var allocator = arena.allocator();
            const key_copy = try allocator.dupe(u8, key_slice);

            try index.put(allocator, key_copy, index_entry);

            current_offset += @sizeOf(main.Header) + header.key_len + header.value_len;

            _ = try file_reader.interface.discard(.limited(header.value_len));
        }

        return .{
            .file = file,
            .arena = arena,
            .index = index,
            .io = io,
        };
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
        const header = main.Header{ .magic = main.MAGIC, .key_len = @intCast(key.len), .value_len = @intCast(value.len) };
        const record_offset = try self.file.length(self.io);
        const val_offset = record_offset + @sizeOf(main.Header) + header.key_len;

        //Initializing buffer to write into the file
        var buffer: [1024]u8 = undefined;
        var file_writer = self.file.writer(self.io, &buffer);

        try file_writer.seekTo(record_offset);

        try file_writer.interface.writeAll(std.mem.asBytes(&header));
        try file_writer.interface.writeAll(key);
        try file_writer.interface.writeAll(value);

        try file_writer.flush();

        const index_entry = IndexEntry{
            .value_len = @intCast(header.value_len),
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
};

test "test init boots on clean file" {
    var db = try BedrockDB.init(std.testing.io, "demo_db.db");

    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, "demo_db.db") catch {};

    try std.testing.expectEqual(0, db.index.count());
}

test "test init builds index from exisiting file" {
    const file = try std.Io.Dir.cwd().createFile(std.testing.io, "create_db.db", .{
        .truncate = false,
        .read = true,
    });
    defer file.close(std.testing.io);
    try main.set(std.testing.io, file, "user", "chish");
    try main.set(std.testing.io, file, "editor", "nvim");
    try main.set(std.testing.io, file, "os", "linux");

    var db = try BedrockDB.init(std.testing.io, "create_db.db");
    defer db.deinit();
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, "create_db.db") catch {};

    try std.testing.expectEqual(3, db.index.count());
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
