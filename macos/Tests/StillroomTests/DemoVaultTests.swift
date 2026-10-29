import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Stillroom

/// Writes a demo vault for screenshots, full of the kind of things people really keep in one: a made-up person's
/// taxes, passport, medical records, legal papers, evidence, logins and two-factor codes. Every name, number and
/// address is invented (card numbers are the public test ones, the 2FA key is the well-known demo key).
/// Runs only when STILLROOM_DEMO_DIR names an empty folder; it writes `Store/` there plus `password.txt`.
/// Open it with a demo copy whose CFFIXED_USER_HOME has that Store at Library/Application Support/Stillroom/Store.
extension VaultFlowTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STILLROOM_DEMO_DIR"] != nil))
    func writesDemoVault() async throws {
        let dir = URL(filePath: ProcessInfo.processInfo.environment["STILLROOM_DEMO_DIR"]!)
        let store = dir.appending(path: "Store")
        VaultStore.rootForTests = store
        let source = dir.appending(path: "source")
        try? FileManager.default.removeItem(at: source)
        // The free tier would stop at 25: lift it with a test key while writing, and leave no licence behind.
        let signer = Curve25519.Signing.PrivateKey()
        License.signerForTests = signer.publicKey
        defer { License.signerForTests = nil }

        let password = "orchard-lantern-quiet-58"
        let state = AppState()
        try await state.create(password: password, touchID: false)
        try state.addLicense(LicenseTests.mint(#"{"v":1,"id":"txn_demo","edition":"personal","seats":1,"name":"Elena Marsh","email":"elena.marsh@fastmail.com","issued":"2026-10-28"}"#, signer))
        _ = try await state.makeKit(threshold: 2, count: 3)

        // Files, in folders, with believable dates.
        let files: [(String, Data, String)] = [
            ("Taxes/2025/2025 Form 1040 – Elena Marsh.pdf", pdf("Form 1040  U.S. Individual Income Tax Return  2025", [
                "Elena R. Marsh                                   SSN  ███-██-4417", "41 Orchard Street, Apt 3B, Somerville, MA 02144",
                "Filing status: Single", "", "1a  Wages, salaries, tips (W-2)                         128,450.00",
                "2b  Taxable interest                                      1,212.87", "3b  Ordinary dividends                                    3,904.11",
                "7   Capital gain                                          6,830.00", "9   Total income                                        140,396.98",
                "11  Adjusted gross income                               134,876.98", "15  Taxable income                                      120,276.98",
                "24  Total tax                                            22,961.40", "25a Federal income tax withheld                         24,880.00",
                "34  Overpaid                                              1,918.60", "35a Refund                                                1,918.60",
            ]), "2026-04-09"),
            ("Taxes/2025/W-2 Quillmere Health 2025.pdf", pdf("Form W-2  Wage and Tax Statement  2025", [
                "Employer: Quillmere Health Partners, LLC  EIN 12-3456789", "Employee: Elena R. Marsh", "",
                "1  Wages, tips, other compensation      128,450.00", "2  Federal income tax withheld          24,880.00",
                "3  Social security wages                128,450.00", "5  Medicare wages and tips              128,450.00",
                "17 State income tax (MA)                 6,231.12",
            ]), "2026-01-28"),
            ("Taxes/2025/1099-INT Chase.pdf", pdf("Form 1099-INT  Interest Income  2025", ["Payer: JPMorgan Chase Bank, N.A.", "Recipient: Elena R. Marsh", "", "1  Interest income   1,212.87"]), "2026-02-11"),
            ("Taxes/2024/2024 Form 1040.pdf", pdf("Form 1040  U.S. Individual Income Tax Return  2024", ["Elena R. Marsh", "", "11  Adjusted gross income   118,204.55", "35a Refund   640.00"]), "2025-04-12"),
            ("Taxes/2024/Amended return 1040-X.pdf", pdf("Form 1040-X  Amended U.S. Individual Income Tax Return", ["Tax year 2024", "Reason: corrected 1099-B cost basis"]), "2025-08-03"),
            ("Identity/Passport – Elena Marsh.jpg", card("PASSPORT", "UNITED STATES OF AMERICA", ["Surname  MARSH", "Given names  ELENA ROSE", "Nationality  USA", "Date of birth  14 MAR 1991", "Passport No.  58392104", "Expires  02 JUN 2033"]), "2024-06-02"),
            ("Identity/Driver's licence (front).jpg", card("MASSACHUSETTS", "DRIVER'S LICENSE", ["MARSH, ELENA R", "41 ORCHARD ST APT 3B", "SOMERVILLE MA 02144", "DOB 03/14/1991", "LIC S83920147", "EXP 03/14/2029"]), "2024-09-19"),
            ("Identity/Driver's licence (back).jpg", card("MASSACHUSETTS", "DRIVER'S LICENSE", ["ORGAN DONOR", "CLASS D", "RESTR NONE"]), "2024-09-19"),
            ("Identity/Birth certificate.pdf", pdf("Commonwealth of Massachusetts  Certificate of Live Birth", ["Name: Elena Rose Marsh", "Date of birth: March 14, 1991", "Place of birth: Worcester, MA"]), "2024-06-02"),
            ("Identity/Social Security card.jpg", card("SOCIAL SECURITY", "THIS NUMBER HAS BEEN ESTABLISHED FOR", ["ELENA ROSE MARSH", "███-██-4417"]), "2024-06-02"),
            ("Medical/MRI lumbar spine – report.pdf", pdf("Mass General Brigham  Radiology Report", ["Patient: Marsh, Elena R.   MRN 4471-2093", "Exam: MRI lumbar spine without contrast", "",
                "Findings: L4-L5 disc protrusion with mild narrowing of the left lateral recess.", "Impression: Findings correlate with left-sided radicular symptoms.", "Recommend PT; follow-up in 12 weeks."]), "2026-02-20"),
            ("Medical/Bloodwork Mar 2026.pdf", pdf("Quest Diagnostics  Lab Results", ["Patient: Elena Marsh", "TSH  4.9 mIU/L (H)", "Ferritin  11 ng/mL (L)", "HbA1c  5.4 %", "Vitamin D  22 ng/mL (L)"]), "2026-03-18"),
            ("Medical/Prescription history.csv", Data("date,medication,dose,prescriber\n2026-03-20,Levothyroxine,50 mcg,Dr. A. Okafor\n2026-02-22,Meloxicam,15 mg,Dr. J. Lindqvist\n2025-11-04,Sertraline,50 mg,Dr. M. Reyes\n".utf8), "2026-03-21"),
            ("Medical/Insurance card – Aetna.jpg", card("aetna", "OPEN ACCESS MANAGED CHOICE", ["Member  ELENA MARSH", "ID  W284719305", "Group  0938471-10-002", "RX BIN 610502"]), "2025-01-07"),
            ("Legal/Will and testament (signed).pdf", pdf("Last Will and Testament of Elena Rose Marsh", ["I, Elena Rose Marsh, of Somerville, Massachusetts, declare this to be my Will.", "Article I. I appoint my sister, Clara Marsh, as Executor.", "Article II. I give my residence and its contents to ..."]), "2025-07-30"),
            ("Legal/Durable power of attorney.pdf", pdf("Durable Power of Attorney", ["Principal: Elena Rose Marsh", "Agent: Clara Marsh", "Effective upon signing; survives incapacity."]), "2025-07-30"),
            ("Legal/Separation agreement – draft 4.pdf", pdf("Separation Agreement  DRAFT 4  Privileged & Confidential", ["Between Elena R. Marsh and Daniel P. Kerr", "1. Custody: ...", "2. Division of property: the condominium at 41 Orchard St ...", "3. Spousal support: none, mutually waived.", "Counsel comments in margin: see section 2(c)."]), "2026-05-11"),
            ("Legal/Lease – 41 Orchard St.pdf", pdf("Residential Lease Agreement", ["Premises: 41 Orchard Street, Apt 3B, Somerville, MA", "Term: Sept 1, 2025 – Aug 31, 2026", "Rent: $2,850 per month"]), "2025-08-14"),
            ("Evidence/2026/Messages 2026-03-14.png", chat(["you need to answer when I call", "I'm at work. I'll call at 6.", "I drove past your building last night", "Please stop. I've asked you not to do that."]), "2026-03-14"),
            ("Evidence/2026/Messages 2026-04-02.png", chat(["why is your location off", "Because it's mine.", "we'll see what the lawyer thinks of that"]), "2026-04-02"),
            ("Evidence/2026/Doorbell camera 2026-04-05.jpg", card("FRONT DOOR", "Apr 5, 2026  11:42 PM", ["Motion detected", "Person at door  2 min 14 s"]), "2026-04-05"),
            ("Finance/Brokerage statement Q3 2026.pdf", pdf("Fidelity Investments  Quarterly Statement  Q3 2026", ["Account ending 8814", "Beginning value  $184,220.17", "Ending value  $191,507.42", "Change  +$7,287.25"]), "2026-10-04"),
            ("Finance/Mortgage pre-approval.pdf", pdf("Rocket Mortgage  Pre-Approval Letter", ["Borrower: Elena R. Marsh", "Approved amount: $640,000", "Valid through: December 31, 2026"]), "2026-09-22"),
            ("Finance/Ledger – setup sheet.pdf", pdf("Ledger Nano X  Recovery Sheet", ["Keep this sheet offline.", "Words 1–24 are stored separately (see Secrets)."]), "2025-12-02"),
            ("Work/Offer letter – Quillmere Health.pdf", pdf("Quillmere Health Partners  Offer of Employment", ["Position: Senior Data Analyst", "Base salary: $132,000", "Start date: January 12, 2026"]), "2025-12-15"),
            ("Work/NDA – signed.pdf", pdf("Mutual Non-Disclosure Agreement", ["Quillmere Health Partners, LLC and Elena R. Marsh"]), "2026-01-12"),
        ]
        var byFolder: [String: [URL]] = [:]
        for (path, data, day) in files {
            let url = source.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Updates.day(day)!.addingTimeInterval(9.5 * 3600)], ofItemAtPath: url.path)
            byFolder[String(path.split(separator: "/").first!), default: []].append(url)
        }
        // Each top folder added whole, so its subfolders come along as folders.
        await state.add(byFolder.keys.sorted().map { source.appending(path: $0) })

        // Notes.
        let notes: [(String, String, String?)] = [
            ("Incident log", "Mar 14 — Drove past the building after 11pm. Saved texts (Evidence/2026).\nMar 29 — Showed up at work. Security walked him out. Badge log requested.\nApr 2 — Asked why my location is off. Screenshot saved.\nApr 5 — Doorbell camera, 11:42 PM. Clip saved.\nApr 8 — Called Officer Brandt, case #26-04417. Told to keep everything dated.", "Evidence"),
            ("Questions for the lawyer", "1. Can the separation agreement include a no-contact clause?\n2. Does the lease in my name alone protect me if he tries to move back in?\n3. Restraining order: what counts as evidence? (log, texts, camera)\n4. Who sees the financial disclosures?", "Legal"),
            ("Recovery codes – Google", "8241 5530\n1904 7726\n6672 0391\n3318 4405\n9057 2864\n4410 7713\n2286 9052\n7731 0648\n5592 3317\n0864 2295", nil),
            ("Therapy – things to bring up", "- Sleep since March\n- Why I still answer when he calls\n- Telling Clara about the will\n- Work: the panic before the Monday review", "Medical"),
            ("Safe deposit box", "Cambridge Savings Bank, Harvard Sq branch\nBox 2217, key in the blue envelope\nInside: original will, passport card, Grandma's ring", nil),
            ("Wedding vows (never sent)", "I kept writing these and deleting them. Keeping one copy here.", nil),
        ]
        for (name, text, folder) in notes { _ = state.newEntry(.note, name: name, content: Data(text.utf8), folder: folder) }

        // Secrets.
        func secret(_ t: Secret.Template, _ values: [String], extra: [Secret.Field] = []) throws -> Data {
            var s = Secret(template: t)
            for (i, v) in values.enumerated() where i < s.fields.count { s.fields[i].value = v }
            s.fields += extra
            return try JSONEncoder().encode(s)
        }
        let totp = { (issuer: String, account: String) in
            Secret.Field(label: "Two-factor", value: "otpauth://totp/\(issuer):\(account)?secret=JBSWY3DPEHPK3PXP&issuer=\(issuer)", concealed: true)
        }
        let secrets: [(String, Data)] = [
            ("Google", try secret(.login, ["accounts.google.com", "elena.marsh91@gmail.com", "vR7#tq-Lm2!pzX9wK4sa"], extra: [totp("Google", "elena.marsh91@gmail.com")])),
            ("Chase", try secret(.login, ["chase.com", "emarsh_0314", "Kq8!rN2v-Lp5sWe7xZ3m"], extra: [totp("Chase", "emarsh_0314")])),
            ("Coinbase", try secret(.login, ["coinbase.com", "elena.marsh@fastmail.com", "j4#Wv9pQ-x2Lr7!mN8tz"], extra: [totp("Coinbase", "elena.marsh@fastmail.com")])),
            ("Fidelity", try secret(.login, ["fidelity.com", "EMarsh8814", "T6-qPz!9wLr2#Xv4kN7s"])),
            ("Apple Account", try secret(.login, ["account.apple.com", "elena.marsh@icloud.com", "pL9!wq2-Zx7#Kv4rT8mN"])),
            ("Aetna member portal", try secret(.login, ["aetna.com", "W284719305", "Bn3#xQ8-vL2!pZ7wK9tr"])),
            ("MyChart – Mass General", try secret(.login, ["patientgateway.massgeneralbrigham.org", "emarsh91", "qW7!nZ2-pL9#xT4vK8sr"])),
            ("Chase Sapphire Visa", try secret(.card, ["Elena R Marsh", "4242 4242 4242 4242", "08/29", "317", "4471"])),
            ("Passport", try secret(.identity, ["Elena Rose Marsh", "US passport", "58392104", "02 Jun 2033"])),
            ("Social Security", try secret(.identity, ["Elena Rose Marsh", "SSN", "912-38-4417", "—"])),
            ("Home Wi-Fi", try secret(.wifi, ["Orchard-3B", "lantern-harbor-pickle-29"])),
            ("Ledger seed phrase", try secret(.other, ["harvest velvet tunnel orphan slim cradle depart echo valley margin ritual sponsor fragile oyster bounce clinic awkward lemon tower ancient pilot hazard noble wisdom"])),
            ("Safe deposit box PIN", try secret(.other, ["0417"])),
        ]
        for (name, data) in secrets { _ = state.newEntry(.secret, name: name, content: data) }

        for (name, tags) in [("Incident log", ["urgent", "lawyer"]), ("Separation agreement – draft 4.pdf", ["lawyer"]), ("Messages 2026-03-14.png", ["evidence"]),
                             ("Messages 2026-04-02.png", ["evidence"]), ("Doorbell camera 2026-04-05.jpg", ["evidence"]), ("2025 Form 1040 – Elena Marsh.pdf", ["taxes"])] {
            if let f = state.files.first(where: { $0.name == name }) { state.setTags(tags, on: f.id) }
        }

        // A decoy with a believable, dull life of its own.
        _ = try await state.setOtherSlot(password: "spring-cleaning-2026")
        state.lock()
        try await state.unlock(password: "spring-cleaning-2026")
        _ = state.newEntry(.note, name: "Groceries", content: Data("oat milk\nlemons\ncoffee\nrice".utf8))
        _ = state.newEntry(.note, name: "Book list", content: Data("Tomorrow, and Tomorrow, and Tomorrow\nThe Overstory".utf8))
        _ = state.newEntry(.secret, name: "Netflix", content: try secret(.login, ["netflix.com", "elena.marsh@fastmail.com", "summer-rain-1991"]))
        state.lock()

        // No licence left behind: the demo app checks keys against the real public key.
        try? FileManager.default.removeItem(at: store.deletingLastPathComponent().appending(path: "License"))
        try Data("\(password)\n".utf8).write(to: dir.appending(path: "password.txt"))
        #expect(state.files.isEmpty)
    }
}

/// A one-page US Letter PDF: a title and lines of text.
private func pdf(_ title: String, _ lines: [String]) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    draw(title, at: CGPoint(x: 54, y: 720), size: 15, bold: true, in: ctx)
    ctx.setStrokeColor(gray: 0.2, alpha: 1); ctx.setLineWidth(0.8)
    ctx.stroke(CGRect(x: 54, y: 706, width: 504, height: 0.5))
    for (i, line) in lines.enumerated() { draw(line, at: CGPoint(x: 54, y: 680 - CGFloat(i) * 20), size: 10.5, mono: line.contains("  "), in: ctx) }
    draw("Page 1 of 1", at: CGPoint(x: 500, y: 40), size: 8, in: ctx)
    ctx.endPDFPage(); ctx.closePDF()
    return data as Data
}

/// An ID-card-like picture: a pale card with a heading and lines.
private func card(_ heading: String, _ sub: String, _ lines: [String]) -> Data {
    image(width: 1012, height: 638) { ctx in
        ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1012, height: 638))
        ctx.setFillColor(CGColor(red: 0.20, green: 0.27, blue: 0.43, alpha: 1)); ctx.fill(CGRect(x: 0, y: 548, width: 1012, height: 90))
        draw(heading, at: CGPoint(x: 40, y: 584), size: 34, bold: true, color: .white, in: ctx)
        draw(sub, at: CGPoint(x: 40, y: 500), size: 22, in: ctx)
        ctx.setFillColor(CGColor(red: 0.78, green: 0.80, blue: 0.85, alpha: 1)); ctx.fill(CGRect(x: 40, y: 150, width: 240, height: 300))
        for (i, l) in lines.enumerated() { draw(l, at: CGPoint(x: 320, y: 420 - CGFloat(i) * 46), size: 26, mono: true, in: ctx) }
    }
}

/// A phone screenshot of a text thread: theirs grey on the left, yours blue on the right, alternating.
private func chat(_ messages: [String]) -> Data {
    image(width: 750, height: 1334, png: true) { ctx in
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 750, height: 1334))
        draw("D", at: CGPoint(x: 360, y: 1230), size: 30, bold: true, in: ctx)
        var y: CGFloat = 1120
        for (i, m) in messages.enumerated() {
            let mine = i % 2 == 1
            let w = min(520, CGFloat(m.count) * 15 + 40)
            let rect = CGRect(x: mine ? 750 - 30 - w : 30, y: y, width: w, height: 70)
            ctx.setFillColor(mine ? CGColor(red: 0.04, green: 0.52, blue: 1, alpha: 1) : CGColor(gray: 0.91, alpha: 1))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)); ctx.fillPath()
            draw(m, at: CGPoint(x: rect.minX + 22, y: rect.minY + 24), size: 24, color: mine ? .white : .black, in: ctx)
            y -= 100
        }
    }
}

private func image(width: Int, height: Int, png: Bool = false, _ paint: (CGContext) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    paint(ctx)
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return out as Data
}

private func draw(_ text: String, at point: CGPoint, size: CGFloat, bold: Bool = false, mono: Bool = false, color: CGColor = .black, in ctx: CGContext) {
    let font = CTFontCreateWithName((mono ? "Menlo" : bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}
