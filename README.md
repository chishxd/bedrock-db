# bedrock-db

A simple, no deps Appen-only Database written in Zig 0.16.

Built without external dependencies, frameworks, or hidden allocations. 
Uses a Bitcask-style in-memory hash index for O(1) disk lookups.

![demo-gif](https://cdn.hackclub.com/01a0a08e-6afe-7416-9406-379ae0bb938e/2026-09-14_21-04-03.gif)

---

## Features

-  Written purely with Zig 0.16 STD Library
-  Key offsets are indexed in a RAM Hash Map on startup, allowing direct single-read disk fetches on `get()`.
-  Keys in RAM live inside a dedicated Arena Allocator, which will clear all memory at once rather than in loops-- which can also cause memory fragmentation
-  Deletes append a tombstone record to preserve append-only values while purging keys from RAM.
-  A `compact()` routine will delete all extra unwanted rows.

---

## On-Disk Binary Format

Every record written to disk consists of a fixed 12-byte header followed by variable-length key and value byte payloads:

```text
┌────────────┬──────────────────────┬──────────────┐
│ magic      │   key_len            │   value_len  │
│ 4 bytes    │   4 bytes            │   4 bytes    │
┼────────────┴──────────────────────┴──────────────┤
│                 key payload                      │
│                                                  │
┼──────────────────────────────────────────────────┼
│                 value payload                    │
└──────────────────────────────────────────────────┘
```

### Struct Definition

```zig
const Header = extern struct {
    magic: [4]u8,   // Expected: "BDRK"
    key_len: u32,   // Length of key in bytes
    value_len: u32, // Length of value in bytes (0 for tombstones)
};
```

---

## Quick Start

Probably you can just download binary from the releases, but if the release does not work, clone and build!

```bash
git clone https://github.com/chishxd/bedrock-db.git && cd bedrock-db
zig build

# The binary should now be located in zig-out/bin
./zig-out/bin/bedrock-db
```

### Example Commands

```bash
# Store a key-value pair
bedrock-db set user goku

# Update the key (appends new record to disk & updates RAM index)
bedrock-db set user ultra_instinct

# Retrieve the latest value (Instant O(1) jump!)
bedrock-db get user
# Output: [FOUND] user = ultra_instinct

# Delete a key (writes a tombstone to disk & removes from RAM index)
bedrock-db del user
# Output: [DELETED] Key 'user' removed

# Query a deleted key
bedrock-db get user
# Output: [NOT FOUND] Key 'user' does not exist
```

### 2. Inspect the Raw Bytes

```bash
xxd data-prod.db
```

You will see the raw `BDRK` header and your keys/values directly on disk.

### 3. Run Unit Tests

```bash
zig test src/db.zig
zig test src/main.zig
```
---

Made with DETERMINATION by @Chish
Licensed with [MIT](LICENSE)
