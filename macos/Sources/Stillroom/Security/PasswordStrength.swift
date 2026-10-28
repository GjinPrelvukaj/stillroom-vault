import Foundation

/// How hard a password is to guess, roughly, in bits: what a guessing program that knows the usual tricks (common
/// words, 1234, qwerty, years, aaaa, p@ssw0rd) would need to try. Not exact; meant to stop the guessable ones while
/// letting long random passwords and a few random words through.
enum PasswordStrength {
    /// Enough that, at Argon2id's cost per guess, a big guessing rig would still need centuries.
    static let enough: Double = 50

    static func isEnough(_ password: String) -> Bool { bits(password) >= enough }

    /// Said under the field while it isn't enough.
    static let advice = "Too easy to guess. Skip common words, years and runs like 1234; a few random words work well."

    static func bits(_ password: String) -> Double {
        let chars = Array(password)
        // Words are looked for in a plain copy: lowercase, look-alike digits and symbols turned back into letters.
        let plain = chars.map { c -> Character in
            let lower = Character(c.lowercased())
            return lookalikes[lower] ?? lower
        }
        var total = 0.0
        var i = 0
        while i < chars.count {
            if let word = longestWord(in: plain, at: i) {
                // A known word costs a guesser a pick from a short list, plus a little for capitals.
                total += 7 + (chars[i..<i + word].contains { $0.isUppercase } ? 1 : 0)
                i += word
            } else if let run = run(in: chars, at: i) {
                total += 4
                i += run
            } else if let year = year(in: chars, at: i) {
                total += 6
                i += year
            } else {
                total += log2(pool(chars[i]))
                i += 1
            }
        }
        return total
    }

    // MARK: Patterns

    private static let lookalikes: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "@": "a", "5": "s",
                                                             "$": "s", "7": "t", "!": "i"]

    /// The words people put in passwords most, from the leaked-password lists everyone's guessers start with.
    private static let words: Set<String> = [
        "password", "passwort", "qwerty", "letmein", "welcome", "admin", "login", "iloveyou", "love", "monkey", "dragon",
        "master", "shadow", "sunshine", "princess", "football", "baseball", "soccer", "basketball", "superman", "batman",
        "trustno", "hello", "freedom", "whatever", "secret", "vault", "test", "guest", "summer", "winter", "spring",
        "autumn", "michael", "jordan", "charlie", "jessica", "ashley", "daniel", "thomas", "hunter", "ranger", "buster",
        "tigger", "pepper", "ginger", "cookie", "chocolate", "flower", "money", "starwars", "pokemon", "minecraft",
        "computer", "internet", "apple", "google", "samsung", "iphone", "mother", "father", "family", "friend", "baby",
        "angel", "lucky", "happy", "killer", "blink", "matrix", "access", "pass", "word", "user", "root", "changeme",
        "default", "secure", "private", "mypassword", "abc", "qwertz", "azerty", "asdf", "zxcv", "kosovo", "prishtina",
    ]
    private static let longestWordLength = words.map(\.count).max() ?? 0

    private static func longestWord(in plain: [Character], at i: Int) -> Int? {
        let longest = min(longestWordLength, plain.count - i)
        guard longest >= 3 else { return nil }
        for length in stride(from: longest, through: 3, by: -1) where words.contains(String(plain[i..<i + length])) {
            return length
        }
        return nil
    }

    /// Three or more of the same character, or in a row: abcd, 4321, qwerty, asdf.
    private static func run(in chars: [Character], at i: Int) -> Int? {
        let lower = chars.map { Character($0.lowercased()) }
        var length = 1
        // The same character over and over.
        while i + length < lower.count, lower[i + length] == lower[i] { length += 1 }
        if length >= 3 { return length }
        // Up or down by one: abc, 987.
        for step in [1, -1] {
            length = 1
            while i + length < lower.count, let a = lower[i + length - 1].asciiValue, let b = lower[i + length].asciiValue,
                  Int(b) - Int(a) == step { length += 1 }
            if length >= 3 { return length }
        }
        // Along a keyboard row, either way.
        for row in rows {
            for line in [row, String(row.reversed())] {
                let line = Array(line)
                guard let start = line.firstIndex(of: lower[i]) else { continue }
                length = 0
                while i + length < lower.count, start + length < line.count, lower[i + length] == line[start + length] { length += 1 }
                if length >= 3 { return length }
            }
        }
        return nil
    }

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890", "qwertzuiop", "yxcvbnm", "azertyuiop"]

    /// A year from 1900 to 2099: birthdays and anniversaries.
    private static func year(in chars: [Character], at i: Int) -> Int? {
        guard i + 4 <= chars.count, let n = Int(String(chars[i..<i + 4])), (1900...2099).contains(n) else { return nil }
        return 4
    }

    /// How many characters of this kind there are to pick from.
    private static func pool(_ c: Character) -> Double {
        if c.isLowercase { return 26 }
        if c.isUppercase { return 26 }
        if c.isNumber { return 10 }
        if c.isASCII { return 33 }
        return 100
    }
}
