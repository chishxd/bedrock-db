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
    index: std.StringHashMap(IndexEntry),
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
        var index: std.StringHashMap(IndexEntry) = .init(arena.allocator());

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

            try index.put(key_copy, index_entry);

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
