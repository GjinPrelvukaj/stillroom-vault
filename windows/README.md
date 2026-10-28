# Stillroom for Windows

The Windows port lives here. It must read and write the format in [`docs/FORMAT.md`](../docs/FORMAT.md).

- [`PORT.md`](PORT.md): the plan, what carries over from the Mac app and what changes, and the security parity plan.
- [`engine/`](engine/): the vault engine in Rust (`stillroom-core`). It builds the Argon2 C from `macos/Sources/CArgon2`, unchanged.
