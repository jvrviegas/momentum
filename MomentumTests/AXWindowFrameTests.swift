import CoreGraphics
import Testing
@testable import Momentum

@MainActor
struct AXWindowFrameTests {
    let frame = CGRect(x: 50, y: 60, width: 400, height: 300)

    @Test func moveOnlyWritesPosition() {
        let target = frame.offsetBy(dx: 100, dy: 50)
        #expect(AXWindow.frameChanges(to: target, from: frame) == [.position(target.origin)])
    }

    @Test func resizeOnlyWritesSizeDuringAnimation() {
        let target = CGRect(origin: frame.origin, size: CGSize(width: 800, height: 600))
        #expect(AXWindow.frameChanges(to: target, from: frame) == [.size(target.size)])
    }

    @Test func simultaneousMoveAndResizeKeepsEdgeClampRepair() {
        let target = CGRect(x: 100, y: 120, width: 800, height: 600)
        #expect(AXWindow.frameChanges(to: target, from: frame) == [
            .size(target.size), .position(target.origin), .size(target.size),
        ])
    }

    @Test func intermediateMoveAndResizeSkipsRedundantSecondSizeWrite() {
        let target = CGRect(x: 100, y: 120, width: 800, height: 600)
        #expect(AXWindow.frameChanges(to: target, from: frame, repairClamping: false) == [
            .size(target.size), .position(target.origin),
        ])
    }

    @Test func unknownIntermediateFrameStillUsesFullRepair() {
        #expect(AXWindow.frameChanges(to: frame, from: nil, repairClamping: false) == [
            .size(frame.size), .position(frame.origin), .size(frame.size),
        ])
    }

    @Test func repeatedFrameDoesNotWrite() {
        #expect(AXWindow.frameChanges(to: frame, from: frame).isEmpty)
    }

    @Test func unknownFrameUsesFullWriteSequence() {
        #expect(AXWindow.frameChanges(to: frame, from: nil) == [
            .size(frame.size), .position(frame.origin), .size(frame.size),
        ])
    }

    @Test func finalResizeCanForceRepairEvenIfLastRequestMatched() {
        #expect(AXWindow.frameChanges(to: frame, from: frame, forceResize: true) == [
            .size(frame.size), .position(frame.origin), .size(frame.size),
        ])
    }
}
