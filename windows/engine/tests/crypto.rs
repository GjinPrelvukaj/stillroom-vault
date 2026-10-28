use stillroom_core::crypto::*;
use stillroom_core::VaultError;

/// Low enough to keep the tests quick, as the Mac tests turn `PasswordCost.current` down.
const QUICK: PasswordCost = PasswordCost { memory_kib: 64, passes: 1, lanes: 1 };

#[test]
fn a_seal_opens_only_with_its_key_and_binding() {
    let key = Key::random();
    let sealed = seal(b"a private note", &key, Some(bound::LIST)).unwrap();
    // Nonce, ciphertext and tag, as CryptoKit's combined form.
    assert_eq!(sealed.len(), 12 + 14 + 16);
    assert_eq!(unseal(&sealed, &key, Some(bound::LIST)).unwrap().as_slice(), b"a private note");

    assert_eq!(unseal(&sealed, &key, Some(bound::SEARCH)).unwrap_err(), VaultError::Damaged);
    assert_eq!(unseal(&sealed, &key, None).unwrap_err(), VaultError::Damaged);
    assert_eq!(unseal(&sealed, &Key::random(), Some(bound::LIST)).unwrap_err(), VaultError::Damaged);

    let mut changed = sealed.clone();
    changed[20] ^= 1;
    assert_eq!(unseal(&changed, &key, Some(bound::LIST)).unwrap_err(), VaultError::Damaged);
    assert_eq!(unseal(&sealed[..20], &key, Some(bound::LIST)).unwrap_err(), VaultError::Damaged);
}

#[test]
fn bindings_name_what_they_bind() {
    assert_eq!(bound::cover("list", "a"), b"Vault cover 4lista");
    assert_eq!(bound::cover_key("b"), b"Vault cover key 4b");
    let id = [0xab; 16];
    assert_eq!(bound::item(&id), [b"Vault item 3".as_slice(), &id].concat());
}

#[test]
fn a_password_key_opens_with_its_password_only() {
    let vault_key = Key::random();
    let sealed = seal_with_password(&vault_key, "correct horse battery", QUICK).unwrap();
    // Mark, three big-endian costs, the salt, then nonce, key and tag.
    assert_eq!(&sealed[..4], b"VA2\x01");
    assert_eq!(&sealed[4..16], [0, 0, 0, 64, 0, 0, 0, 1, 0, 0, 0, 1]);
    assert_eq!(sealed.len(), 32 + 12 + 32 + 16);

    let opened = open_with_password(&sealed, "correct horse battery").unwrap();
    assert_eq!(opened.as_bytes(), vault_key.as_bytes());
    assert_eq!(open_with_password(&sealed, "wrong horse").unwrap_err(), VaultError::WrongPassword);
}

#[test]
fn doctored_costs_are_damaged_not_run() {
    let sealed = seal_with_password(&Key::random(), "pw", QUICK).unwrap();
    let with_cost = |at: usize, value: u32| {
        let mut doctored = sealed.clone();
        doctored[at..at + 4].copy_from_slice(&value.to_be_bytes());
        open_with_password(&doctored, "pw").unwrap_err()
    };
    assert_eq!(with_cost(4, 4 * 1024 * 1024), VaultError::Damaged); // 4 GiB of memory
    assert_eq!(with_cost(8, 32), VaultError::Damaged); // 32 passes
    assert_eq!(with_cost(12, 0), VaultError::Damaged); // no lanes
    assert_eq!(open_with_password(b"not a key file at all, not at all", "pw").unwrap_err(), VaultError::Damaged);
}

#[test]
fn padding_rounds_up_by_at_most_twelve_percent() {
    assert_eq!(padded_length(0), Some(0));
    assert_eq!(padded_length(1), Some(1));
    assert_eq!(padded_length(100), Some(104));
    // Past what any file can be: no wrap-around, just None.
    assert_eq!(padded_length(u64::MAX), None);
    assert!(padded_length(1 << 40).unwrap() >= 1 << 40);
    let mut previous = 0;
    for n in (2..2_000_000).step_by(997) {
        let padded = padded_length(n).unwrap();
        assert!(padded >= n && padded >= previous);
        assert!((padded - n) as f64 <= n as f64 * 0.12, "{n} -> {padded}");
        previous = padded;
    }
}

#[test]
fn recovery_codes_are_five_groups_without_look_alikes() {
    let code = make_recovery_code();
    let groups: Vec<&str> = code.split('-').collect();
    assert_eq!(groups.len(), 5);
    assert!(groups.iter().all(|g| g.len() == 5));
    assert!(!code.contains(['0', 'O', '1', 'I', 'L']));
    assert_ne!(code, make_recovery_code());
    assert_eq!(*normalized_recovery_code(&code.to_lowercase().replace('-', " ")), code.replace('-', ""));
}
