# Stillroom for Windows

The Windows port lives here. It must read and write the format in [`docs/FORMAT.md`](../docs/FORMAT.md).

- [`PORT.md`](PORT.md): the plan, what carries over from the Mac app and what changes, and the security parity plan.
- [`SECURITY.md`](SECURITY.md): what the Windows app protects against and what it doesn't, rule by rule against `docs/SECURITY.md`.
- [`app/`](app/): the WinUI 3 app.
- `make-app.ps1`: the app as it ships, in `build/Stillroom`, checked for networking by [`tools/CheckOffline`](tools/CheckOffline/Program.cs) and signed by `sign.ps1` when given a certificate.
- [`engine/`](engine/): the vault engine in Rust (`stillroom-core`). It builds the Argon2 C from `macos/Sources/CArgon2`, unchanged.
