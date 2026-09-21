# Writing get() function as systems and Zig beginner

So... I would need a buffer to store the key temporarily, then check if the
content in buffer and the key passed as argument to the function matches.
If YES, then return the value, else seek to the next value.len

So... yeah My idea worked.. I will document what exactly worked in code itself

# Pilot version works!

Pilot version works!! It is slow, ineffecient, but yeah it works
Now I am thinking of what to work on for v2, will add it as a small TODO below

## 1. In-Memory loading (DONE)

So yeah, we are reading from disk so many times.. It is slow and we are reading
from byte 0 to EOF every-time as my DB is append-only.

So I was thinking of.. prolly building a HashMap index every time the app is initialized
is much faster. Then I can carry queries on HashMap directly.
And hashmap won't keep dupes, more faster! Which will also allow me to maybe
implement a compact() function later 3c

### How I actually did it:

So, I wanted to separate concerns from main.zig to only initialize the CLI and
isolated the actual engine implementation in db.zig. Which can now init the struct
with path to DB file, arena for heap allocations, an UnManaged HashMap for indexing
So we only read the file ones, and don't need to read() on disk to find string.
We can just query the hashmap, it will give us offset to the value the key holds
and return null if key was never in the HashMap.

HEHEHEHE This is all so fun.. And I am NOT using any AI to make this work, which
makes every small step much more rewarding.

## 2. Better deletions (DONE)

So.. Right now you can't really "Delete" any fields, So maybe I could, just update
that field to have value_len 0, Yeah it still wastes some bytes.. I could find a fix for
it in future

### What I ended up doing:

I added new method to BedrockDB, currently all the functions are in a single file,
So, the thing I do which "deletes" the value for UX is by removing the pair from
Index HashMap and creating a "Tombstone" in actual file, which will annotate the deletion
of the value. So the tombstone is nothing but the regular Header, key and val-
wait, value length is 0 in header! Yeah that's right. I was thinking how would I let
program know that the key is actually deleted, so I store the Header and key as regularly do,
but instead of storing value, I change key_len in Header to be 0 and never write a key
The `header.key_len` let's me detect the tombstone and skip it.

### So, what's next?

Imma add CLI option for delete for now.. Let's see, if I should make a print Table
type of output in CLI, for better UX. Or work on core behaviour, like I was thinking
that maybe I could write a compaction method which will rewrite the file by omitting
all the tombstone values completely, like only based on HashMap, so we won't have tombstones
neither would we have previously added value which was later deleted.
