import CoreGraphics
import Testing
@testable import Momentum

@MainActor
struct WindowAnimationTests {
    let start = CGRect(x: 0, y: 0, width: 400, height: 300)
    let target = CGRect(x: 200, y: 100, width: 800, height: 600)

    @Test func easesMovementAndResizeAndFinishesExactly() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        #expect(animation.frames(at: 0)[1] == start)
        #expect(animation.frames(at: 0.1)[1] == CGRect(x: 175, y: 87.5, width: 750, height: 562.5))
        #expect(animation.frames(at: 0.2)[1] == target)
        #expect(!animation.isActive)
        #expect(animation.frames(at: 1).isEmpty)
    }

    @Test func unchangedTargetDoesNotRestartAnimation() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let halfway = animation.frames(at: 0.1)
        animation.retarget(to: [1: target], currentFrames: halfway, at: 0.1)
        #expect(animation.frames(at: 0.2)[1] == target)
        #expect(!animation.isActive)
    }

    @Test func newTargetStartsFromActualFrameWithoutQueuing() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let actual = CGRect(x: 80, y: 40, width: 500, height: 350)
        animation.retarget(to: [1: start], currentFrames: [1: actual], at: 0.1)
        #expect(animation.frames(at: 0.1)[1] == actual)
        #expect(animation.frames(at: 0.3)[1] == start)
        #expect(!animation.isActive)
    }

    @Test func removedWindowsAndAlreadyPlacedWindowsAreNotAnimated() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target, 2: target], currentFrames: [1: start, 2: start], at: 0)
        animation.retarget(to: [1: target, 3: start, 4: target], currentFrames: [1: start, 3: start], at: 0.1)
        #expect(animation.frames(at: 0.15).keys.sorted() == [1])
    }

    @Test func cancelStopsAllUpdates() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        animation.cancel()
        #expect(!animation.isActive)
        #expect(animation.frames(at: 0.1).isEmpty)
    }

    @Test func delayedTickStillFinishesAtTarget() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        #expect(animation.frames(at: 3)[1] == target)
        #expect(!animation.isActive)
    }
}
