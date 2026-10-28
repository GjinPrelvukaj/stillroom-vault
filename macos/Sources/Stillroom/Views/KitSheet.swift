import AppKit
import PDFKit
import SwiftUI

/// Making an emergency kit: how many pieces and how many open it, then the pieces, printed once on paper.
struct KitSheet: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var plan = Plan.twoOfThree
    @State private var codes: [String]?
    @State private var making = false
    @State private var printed = false
    @State private var problem: String?

    enum Plan: String, CaseIterable, Identifiable {
        case twoOfTwo = "2 of 2", twoOfThree = "2 of 3", threeOfFive = "3 of 5"
        var id: String { rawValue }
        var threshold: Int { self == .threeOfFive ? 3 : 2 }
        var count: Int { self == .twoOfTwo ? 2 : self == .twoOfThree ? 3 : 5 }
        var example: String {
            switch self {
            case .twoOfTwo: "Both pieces are needed. Losing either one makes the kit useless."
            case .twoOfThree: "For example: your partner, your lawyer, and your safe. Any two together open it."
            case .threeOfFive: "For a family: five people, any three together open it. Two alone never can."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            if let codes { pieces(codes) } else { choose }
            if let problem { Text(problem).font(Kit.quiet).foregroundStyle(.red.opacity(0.85)) }
        }
        .padding(Kit.Space.edge)
        .frame(width: 480)
        .background(Color.ground)
        .interactiveDismissDisabled(codes != nil)
        .hiddenFromCapture()
    }

    private var choose: some View {
        Group {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Emergency kit").font(Kit.title)
                Text("Printed pieces for people you trust, so they can open the vault if something happens to you. One piece alone opens nothing. No server and no account are involved.")
                    .font(Kit.body).opacity(0.5).fixedSize(horizontal: false, vertical: true)
            }
            Segments(selection: $plan, options: Plan.allCases.map { ($0, $0.rawValue) })
            Text(plan.example).font(Kit.quiet).opacity(0.55).fixedSize(horizontal: false, vertical: true)
            if state.hasKit {
                Text("A new kit stops the old pieces opening this vault. Backups made before it still open with them.").font(Kit.quiet).foregroundStyle(.orange.opacity(0.85))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.quiet).keyboardShortcut(.cancelAction)
                Button(making ? "Making…" : "Make Kit", action: make).buttonStyle(.primary).keyboardShortcut(.defaultAction)
                    .disabled(making)
            }
        }
    }

    private func pieces(_ codes: [String]) -> some View {
        Group {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Print the pieces").font(Kit.title)
                Text("One page per piece, with plain instructions on it. Print on paper; don't save it as a PDF or take a photo. They won't be shown again.")
                    .font(Kit.body).opacity(0.5).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(codes.indices, id: \.self) { i in
                    if i > 0 { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1) }
                    HStack {
                        Text("Piece \(i + 1)").font(Kit.quiet).opacity(0.5).frame(width: 56, alignment: .leading)
                        Text(codes[i]).font(.system(size: 11.5, weight: .medium, design: .monospaced)).textSelection(.disabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .rowPanel()
            HStack {
                Spacer()
                Button("Print Pieces…") { KitPrint.run(codes, threshold: plan.threshold); printed = true }
                    .buttonStyle(printed ? .secondary : .primary)
                Button("Done") { dismiss() }.buttonStyle(printed ? .primary : .secondary).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func make() {
        making = true
        Task {
            do { codes = try await state.makeKit(threshold: plan.threshold, count: plan.count) } catch { problem = ActivityLog.failed(error, error.localizedDescription) }
            making = false
        }
    }
}

/// The printed pages: one per piece, black on white, saying what it is and what to do with it.
enum KitPrint {
    @MainActor static func run(_ codes: [String], threshold: Int) {
        let data = NSMutableData()
        // A4; scaled to fit whatever paper the printer has.
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        let made = Date.now.formatted(date: .long, time: .omitted)
        for (i, code) in codes.enumerated() {
            let page = KitPage(code: code, number: i + 1, count: codes.count, threshold: threshold, made: made)
                .frame(width: box.width, height: box.height)
            ImageRenderer(content: page).render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        guard let document = PDFDocument(data: data as Data),
              let operation = document.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: false) else { return }
        operation.jobTitle = "Stillroom emergency kit"
        operation.run()
    }
}

private struct KitPage: View {
    let code: String
    let number: Int
    let count: Int
    let threshold: Int
    let made: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VAULT EMERGENCY KIT").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.gray)
                Text("Piece \(number) of \(count)").font(.system(size: 30, weight: .bold))
                Text("Any \(threshold) of the \(count) pieces together open the vault. This piece on its own opens nothing.")
                    .font(.system(size: 13))
            }
            Text(code)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .padding(.vertical, 18).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 8) {
                Text("How to use it").font(.system(size: 14, weight: .semibold))
                Text("1.  On the Mac with Stillroom, open Stillroom and click Use Emergency Kit on the lock screen.")
                Text("2.  Type in this piece and \(threshold == 2 ? "one other" : "\(threshold - 1) others"), one per box. Capitals, dashes and spaces don't matter.")
                Text("3.  Choose a new password for the vault when asked.")
                Text("If Stillroom isn't available, the free open-source tool stillroom-open opens the vault with the same pieces (see tools/stillroom-open.py in Stillroom's source).")
                    .foregroundStyle(.gray)
            }
            .font(.system(size: 12.5))
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep it safe").font(.system(size: 14, weight: .semibold))
                Text("Somewhere you'd keep a will or a passport: a safe, a lockbox, with your lawyer's papers. Don't photograph it or keep it on a computer or phone.")
            }
            .font(.system(size: 12.5))
            Spacer()
            HStack {
                Text("Given to: ________________________________").font(.system(size: 12.5))
                Spacer()
                Text("Made \(made)").font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
        .foregroundStyle(.black)
        .padding(56)
        .background(.white)
    }
}
