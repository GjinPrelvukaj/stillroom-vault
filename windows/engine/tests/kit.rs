//! The emergency kit, as `EmergencyKitTests` checks it on the Mac.

use stillroom_core::kit::{code, join, password, piece, split, KitProblem};

#[test]
fn any_threshold_of_the_pieces_gives_the_secret_back() {
    let secret: [u8; 16] = *b"sixteen secrets!";
    for (threshold, count) in [(2u8, 2u8), (2, 5), (3, 5), (5, 5), (10, 12)] {
        let pieces = split(&secret, threshold, count);
        assert_eq!(pieces.len(), usize::from(count));
        // Every run of `threshold` pieces, starting anywhere.
        for start in 0..usize::from(count) {
            let chosen: Vec<_> = (0..usize::from(threshold)).map(|i| pieces[(start + i) % pieces.len()].clone()).collect();
            assert_eq!(*join(&chosen).unwrap(), secret, "{threshold} of {count}, from {start}");
        }
        if threshold > 2 {
            // One short says how many it needs, rather than giving a wrong secret.
            assert_eq!(join(&pieces[..usize::from(threshold) - 1]), Err(KitProblem::NotEnough(threshold)));
        }
    }
}

#[test]
fn pieces_read_back_as_they_were_written() {
    for p in split(&[0xA5; 16], 3, 7) {
        let written = code(&p);
        assert!(written.starts_with("VK-"));
        assert_eq!(written.len(), "VK-".len() + 34 + 8, "34 characters in groups of four");
        assert_eq!(piece(&written).unwrap(), p);
        assert_eq!(piece(&written.to_lowercase().replace('-', " ")).unwrap(), p);
    }
}

#[test]
fn a_mistyped_piece_is_caught() {
    let written = code(&split(&[7; 16], 2, 2)[0]);
    assert_eq!(piece(&written[..written.len() - 1]), Err(KitProblem::Mistyped));
    // One stray 0 at the end only adds padding bits and reads the same, on the Mac too; two can't.
    assert!(piece(&format!("{written}0")).is_ok());
    assert_eq!(piece(&format!("{written}00")), Err(KitProblem::Mistyped));
    assert_eq!(piece(&written.replace('-', "U")), Err(KitProblem::Mistyped), "U isn't in the alphabet");
    let mut swapped: Vec<char> = written.chars().collect();
    let (a, b) = (5, 6);
    if swapped[a] != swapped[b] {
        swapped.swap(a, b);
        assert_eq!(piece(&swapped.into_iter().collect::<String>()), Err(KitProblem::Mistyped));
    }
}

#[test]
fn the_secret_seals_as_lowercase_hex() {
    assert_eq!(password(&[0x00, 0x0f, 0xa0, 0xff, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]).as_str(), "000fa0ff0102030405060708090a0b0c");
}
