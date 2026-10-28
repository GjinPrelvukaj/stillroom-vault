import Testing
@testable import Stillroom

/// Guessable passwords are refused even when long enough; random ones and a few random words pass.
@Test(arguments: ["Password12345", "P@ssw0rd2024!", "qwertyuiop12", "aaaaaaaaaaaa", "ilovemycat123", "MyDogMax2019!",
                  "letmein123456", "Summer2026!!!", "abcdefghijkl", "123456789012", "Kosovo2008!!!"])
func guessablePasswordsAreRefused(_ password: String) {
    #expect(!PasswordStrength.isEnough(password), "\(password): \(PasswordStrength.bits(password)) bits")
}

@Test(arguments: ["k8#Pq2!xVz9m", "correct horse battery staple", "purple elephant dancing slowly", "tVq9-Lm3x-Rr8w",
                  "my blue bicycle rusts in rain"])
func strongPasswordsPass(_ password: String) {
    #expect(PasswordStrength.isEnough(password), "\(password): \(PasswordStrength.bits(password)) bits")
}
