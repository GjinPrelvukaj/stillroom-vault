import Foundation

/// A secret: a few labelled fields (a login's username and password, a card's number), sealed like any file.
/// Concealed fields show as dots until asked and copy to a clipboard that empties itself.
struct Secret: Codable, Hashable, Sendable {
    var template: Template
    var fields: [Field]

    struct Field: Identifiable, Codable, Hashable, Sendable {
        var id = UUID()
        var label: String
        var value: String = ""
        var concealed = false
    }

    enum Template: String, Codable, CaseIterable, Sendable {
        case login, card, wifi, identity, other

        var title: String {
            switch self {
            case .login: "Login"
            case .card: "Card"
            case .wifi: "Wi-Fi"
            case .identity: "ID"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .login: "person.badge.key"
            case .card: "creditcard"
            case .wifi: "wifi"
            case .identity: "person.text.rectangle"
            case .other: "key.horizontal"
            }
        }

        /// The fields a new secret of this kind starts with; more can be added.
        var starting: [Field] {
            switch self {
            case .login: [.init(label: "Website"), .init(label: "Username"), .init(label: "Password", concealed: true)]
            case .card: [.init(label: "Name on card"), .init(label: "Number", concealed: true), .init(label: "Expires"),
                         .init(label: "Security code", concealed: true), .init(label: "PIN", concealed: true)]
            case .wifi: [.init(label: "Network"), .init(label: "Password", concealed: true)]
            case .identity: [.init(label: "Full name"), .init(label: "Document"), .init(label: "Number", concealed: true),
                             .init(label: "Expires")]
            case .other: [.init(label: "Secret", concealed: true)]
            }
        }
    }

    init(template: Template) {
        self.template = template
        fields = template.starting
    }

    /// What shows under its name in a list: the first field that isn't concealed and isn't empty.
    var summary: String {
        fields.first { !$0.concealed && !$0.value.isEmpty }?.value ?? template.title
    }
}

/// A random password: 20 characters from letters, digits and a few symbols that survive any website's rules,
/// without look-alikes. About 115 random bits.
func generatedPassword(length: Int = 20) -> String {
    let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.!@#%")
    var random = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in alphabet.randomElement(using: &random)! })
}
