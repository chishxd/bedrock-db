# bedrock-db

A zero-dependency, crash-resilient, append-only binary key-value storage engine written from scratch in pure **Zig 0.16**.

Built without external dependencies, frameworks, or hidden allocations. Uses a Bitcask-style in-memory hash index for $O(1)$ disk lookups.

![demo-gif](https://cdn.hackclub.com/01a0a08e-6afe-7416-9406-379ae0bb938e/2026-09-14_21-04-03.gif)

---

## Features

- **Zero External Dependencies:** Built purely on the Zig 0.16 standard library.
- **$O(1)$ In-Memory Index (Bitcask Style):** Key offsets are indexed in a RAM Hash Map on startup, allowing direct single-read disk fetches on `get()`.
- **Arena-Backed Memory:** Keys in RAM live inside a dedicated Arena Allocator, eliminating memory fragmentation and wiping all index memory simultaneously on shutdown.
- **Tombstone Deletions:** Deletes append a zero-value tombstone record to preserve append-only invariants while purging keys from RAM.
- **Log Compaction:** A `compact()` routine reclaims disk space by rewriting only live records to a fresh file and atomically replacing the bloated log.
- **Full Test Suite:** 7 automated tests verifying end-to-end lifecycle, reboots, tombstone persistence, and zero memory leaks. (Well, I jst tried using this new approach where I would write tests for what I expect and make my code work around it, and it helped me build a lot of logic, and I get professional looking tests, so it's a win-win)

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
    value_len: u32, // Length of value in bytes (0 for tombstones)
};
```

---

## Quick Start

### 1. Build & Run

```bash
# Store a key-value pair
zig build run -- set user goku

# Update the key (appends new record to disk & updates RAM index)
zig build run -- set user ultra_instinct

# Retrieve the latest value (Instant O(1) jump!)
zig build run -- get user
# Output: [FOUND] user = ultra_instinct

# Delete a key (writes a tombstone to disk & removes from RAM index)
zig build run -- del user
# Output: [DELETED] Key 'user' removed

# Query a deleted key
zig build run -- get user
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
