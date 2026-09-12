const std = @import("std");

// I am thinking of... defining a simple struct to read the blob
// This struct must be able to store the key and value...
// But if I store it as a binary, but not a JSON file, then I would need some
// Kinda Identifier to check if the Blob is a DB object or not...
// Then how do I identify a KEY and a VALUE?? Maybe I could store len of key
// and len of value.. Or maybe a HEX value to indicate start and end of the values
// Then I would be wasting 4 u8 integers, but if I just store the length of key and
// value, it will be cheaper.. As the key can start immediately after Identifier
// So the final structure could be an Identifier, then len of key, len of value
// then actual key and value

const MAGIC: [4]u8 = "BDRK".*;

/// Fixed-sized Header to Identify DB data from blob
const Header = struct {
    magic: u32,
    key_len: u16,
    value_len: u32,
};

pub fn main() !void {
    std.debug.print("Size of header is: {d}\n", .{@sizeOf(Header)});
}
