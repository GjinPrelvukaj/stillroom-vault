# CArgon2

The Argon2 reference implementation, unchanged: https://github.com/P-H-C/phc-winner-argon2, release `20190702`
(commit 62358ba2123abd17fccf2a108a301d4b52c01a7c). Licensed CC0 1.0 or Apache 2.0 (`LICENSE`).

Only the files the portable build needs are here: `argon2.c`, `core.c`, `encoding.c`, `ref.c` (no SSE; Stillroom is
arm64), `thread.c`, BLAKE2b, and `include/argon2.h`. Don't edit them; to update, copy the same files from a newer
release and run `swift test --filter Argon2`, which checks them against the RFC 9106 vector, libargon2's known
answers and the Swift implementation kept in the tests.
