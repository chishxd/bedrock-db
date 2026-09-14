# bedrock-db

A zero-dependency, crash-resilient, append-only binary key-value storage engine written from scratch in pure **Zig 0.16**.

Built without external dependencies, frameworks, or hidden allocations.. Helped me learn ALOT

![demo-gif](https://cdn.hackclub.com/01a0a08e-6afe-7416-9406-379ae0bb938e/2026-09-14_21-04-03.gif)

---

## Features

- **Zero External Dependencies:** Built purely on the Zig 0.16 standard library.
- **Deterministic Binary Layout:** Uses an `extern struct` with zero padding bytes for optimal CPU cache alignment.
- **Append-Only Architecture:** Fast writes via sequential disk appending; updates and historical states are preserved.
- **FourCC Magic Header:** Identifies database files with `BDRK` (`0x4244524B`) magic bytes to prevent data corruption.
- **Memory-Safe Scanner:** `get()` sequentially traverses records, resolving latest updates while maintaining zero memory leaks.
- **Full Unit Test Suite:** Includes automated testing with `std.testing.allocator` to verify zero memory leaks.

---

## On-Disk Binary Format

Every record written to disk consists of a **fixed 12-byte header** followed by variable-length key and value byte payloads:

```text
+-------------------+--------------------+--------------------+
|  magic ([4]u8)    |   key_len (u32)    |  value_len (u32)   |
|     4 Bytes       |      4 Bytes       |      4 Bytes       |
+-------------------+--------------------+--------------------+
|                      key payload (key_len bytes)            |
+-------------------------------------------------------------+
|                     value payload (value_len bytes)         |
+-------------------------------------------------------------+
```

### Struct Definition

```zig
const Header = extern struct {
    magic: [4]u8,   // Expected: "BDRK"
    key_len: u32,   // Length of key in bytes
    value_len: u32, // Length of value in bytes
};
```

_Note: By widening `key_len` to `u32`, all fields are naturally aligned on 4-byte boundaries, eliminating compiler-inserted padding bytes._

---

## Quick Start

### 1. Build & Run

```bash
# Store a key-value pair
zig build run -- set user goku

# Update the key (appends new record to disk)
zig build run -- set user ultra_instinct

# Retrieve the latest value
zig build run -- get user
# Output: [FOUND] user = ultra_instinct

# Query a non-existent key
zig build run -- get missing_key
# Output: [NOT FOUND] Key 'missing_key' does not exist
```

Maybe I would just publish a binary :p

### 2. Inspect the Raw Bytes

```bash
xxd data.db
```

You will see the raw `BDRK` header and your keys/values directly on disk.

### 3. Run Unit Tests

```bash
zig test src/main.zig
```

---

## Design Decisions & Trade-offs

1. **Prefix Length instead of using Delimiters:** Keys and values are prefixed by their lengths rather than using delimiter/sentinel bytes (like `\0`), which allows any arbitrary type of data.. In case binary has delimiter, also delimiters would take more space than prefixing i guess.
2. **Caller Owns the Memory:** `get()` accepts an explicit `std.mem.Allocator` from the caller. The storage engine does not assume heap strategies—it works with the base interface itself, Which will let me add any type of allocator I want instead of having to mess with internal function.
