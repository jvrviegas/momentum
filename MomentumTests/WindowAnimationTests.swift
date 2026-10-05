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

    @Test func retargetPreservesMovementAndResizeVelocity() throws {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let current = try #require(animation.frames(at: 0.1)[1])
        let nextTarget = CGRect(x: 400, y: 200, width: 1000, height: 700)
        animation.retarget(to: [1: nextTarget], currentFrames: [1: current], at: 0.1)
        let dt = 0.000001
        let next = try #require(animation.frames(at: 0.1 + dt)[1])
        // The original cubic ease-out's velocity at its midpoint, in points/second.
        #expect(abs((next.minX - current.minX) / dt - 750) < 0.2)
        #expect(abs((next.minY - current.minY) / dt - 375) < 0.2)
        #expect(abs((next.width - current.width) / dt - 1500) < 0.2)
        #expect(abs((next.height - current.height) / dt - 1125) < 0.2)
        #expect(animation.frames(at: 0.3)[1] == nextTarget)
    }

    @Test func reversalDeceleratesInsteadOfInstantlyChangingDirection() throws {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let current = try #require(animation.frames(at: 0.1)[1])
        animation.retarget(to: [1: start], currentFrames: [1: current], at: 0.1)
        let next = try #require(animation.frames(at: 0.100001)[1])
        #expect(next.minX > current.minX)
        #expect(animation.frames(at: 0.3)[1] == start)
    }

    @Test func nativeClampingDoesNotCarryImaginaryVelocity() throws {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let actual = CGRect(x: 50, y: 30, width: 450, height: 320)
        animation.retarget(to: [1: start], currentFrames: [1: actual], at: 0.1)
        let next = try #require(animation.frames(at: 0.100001)[1])
        #expect(abs((next.minX - actual.minX) / 0.000001) < 0.1)
        #expect(abs((next.width - actual.width) / 0.000001) < 0.1)
    }

    @Test func resizeMomentumNeverProducesInvalidSizes() throws {
        var animation = WindowAnimation()
        let large = CGRect(x: 0, y: 0, width: 10000, height: 10000)
        let small = CGRect(x: 0, y: 0, width: 1, height: 1)
        animation.retarget(to: [1: small], currentFrames: [1: large], at: 0)
        let current = try #require(animation.frames(at: 0.15)[1])
        let nextTarget = CGRect(origin: current.origin, size: CGSize(width: current.width + 10, height: current.height + 10))
        animation.retarget(to: [1: nextTarget], currentFrames: [1: current], at: 0.15)
        for time in stride(from: 0.15, to: 0.35, by: 0.005) {
            let frame = try #require(animation.frames(at: time)[1])
            #expect(frame.width >= 1 && frame.height >= 1)
        }
        #expect(animation.frames(at: 0.35)[1] == nextTarget)
    }

    @Test func retargetUsesLastDisplayedVelocityBetweenRefreshes() throws {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let displayed = try #require(animation.frames(at: 0.1)[1])
        let nextTarget = CGRect(x: 400, y: 200, width: 1000, height: 700)
        // The command lands between display callbacks; AX still reports the last displayed frame.
        animation.retarget(to: [1: nextTarget], currentFrames: [1: displayed], at: 0.116)
        let next = try #require(animation.frames(at: 0.116001)[1])
        #expect(abs((next.minX - displayed.minX) / 0.000001 - 750) < 0.2)
    }

    @Test func crossingTargetWithMomentumDoesNotEndBeforeDeadline() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        let nextTarget = CGRect(x: 150, y: 75, width: 700, height: 525)
        animation.retarget(to: [1: nextTarget], currentFrames: [1: start], at: 0)
        #expect(animation.frames(at: 0.1)[1] == nextTarget)
        #expect(animation.isActive)
        #expect(animation.frames(at: 0.2)[1] == nextTarget)
        #expect(!animation.isActive)
    }

    @Test func delayedTickStillFinishesAtTarget() {
        var animation = WindowAnimation()
        animation.retarget(to: [1: target], currentFrames: [1: start], at: 0)
        #expect(animation.frames(at: 3)[1] == target)
        #expect(!animation.isActive)
    }
}
