//! The same known answers the Mac app checks in macos/Tests/StillroomTests/Argon2Tests.swift, so the shared C gives the
//! same keys built for Windows as for the Mac.

use stillroom_core::argon2::argon2id;
use stillroom_core::VaultError;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// RFC 9106 section 5.3: H0 with a secret and associated data, H', G and four lanes.
#[test]
fn argon2id_matches_the_rfc_vector() {
    let tag = argon2id(&[1; 32], &[2; 16], 32, 3, 4, 32, &[3; 8], &[4; 12]).unwrap();
    assert_eq!(hex(&tag), "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659");
}

/// A password, a salt, its memory (KiB), passes and lanes, and the key libargon2 gives.
type Case<'a> = (&'a str, &'a [u8], u32, u32, u32, &'a str);

/// Answers from libargon2, at costs the RFC vector doesn't reach.
#[test]
fn argon2id_matches_libargon2_answers() {
    let cases: [Case; 3] = [
        ("password", b"somesalt", 1024, 1, 1, "c8e9aedc956f6a7dff0a4d42940df628623f328ea1235005abac933c57093e23"),
        ("password", b"somesalt", 4099, 2, 4, "2b6c3ddf0aa362e65218e07fc58dacf51d696bfdf641949a4875e9e1522df718"),
        ("pässwörd 🔐", &[7; 16], 65536, 3, 1, "b2411a53d160ea1d19d318c6eac6d2950268c54db0814feae2c999c64406e089"),
    ];
    for (password, salt, memory_kib, passes, lanes, expected) in cases {
        let tag = argon2id(password.as_bytes(), salt, memory_kib, passes, lanes, 32, &[], &[]).unwrap();
        assert_eq!(hex(&tag), expected, "m {memory_kib} t {passes} p {lanes}");
    }
}

/// A password must stretch to the same key every time, and a fresh salt must give a different one.
#[test]
fn argon2id_is_stable_and_salt_sensitive() {
    let tag = |salt: u8| argon2id(b"correct horse battery", &[salt; 16], 64, 2, 2, 32, &[], &[]).unwrap();
    assert_eq!(*tag(7), *tag(7));
    assert_ne!(*tag(7), *tag(8));
}

/// Costs no key should carry are refused, not crashed on.
#[test]
fn impossible_costs_are_refused() {
    assert_eq!(argon2id(b"x", &[0; 16], 8, 0, 1, 32, &[], &[]).unwrap_err(), VaultError::Damaged);
}
