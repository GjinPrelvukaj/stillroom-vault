import Foundation
import Testing
@testable import Stillroom

/// The stall detector reads where the main thread is while it's busy: here, asleep inside this very test.
@MainActor @Test func capturesTheMainThreadWhileItIsBusy() {
    MainThreadStack.remember()
    nonisolated(unsafe) var stack: [UInt] = []
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 0.15)
        stack = MainThreadStack.capture()
        done.signal()
    }
    Thread.sleep(forTimeInterval: 0.5)
    done.wait()
    let frames = stack.map(MainThreadStack.describe)
    #expect(frames.contains { $0.contains("sleep") })
    #expect(frames.contains { $0.contains("capturesTheMainThreadWhileItIsBusy") })
    // Busy in our own code is a stall, not the run loop idling.
    #expect(!MainThreadStack.isWaiting(stack))
}

@Test func longFrameNamesAreShortenedForTheLog() {
    let frame = "Stillroom  closure #1 in closure #1 () -> SwiftUI.TupleView<(SwiftUI.Button<SwiftUI.Text>, SwiftUI.Button<SwiftUI.Text>)> in Stillroom.VaultApp.body.getter + 156"
    #expect(MainThreadStack.shortened(frame) == "Stillroom  closure #1 in closure #1 () -> SwiftUI.TupleView in Stillroom.VaultApp.body.getter + 156")
}
