import CoreGraphics
import Foundation

/// Native transfer completion requires stable Space membership plus independent AX/WindowServer geometry.
enum DisplayMover {
    enum MoveError: LocalizedError, Equatable {
        case destinationChanged, windowUnavailable, invalidFrame, frameWriteFailed, timedOut
        var errorDescription: String? {
            switch self {
            case .destinationChanged: "The destination display or Desktop changed during the move. Try again."
            case .windowUnavailable: "The window is no longer available."
            case .invalidFrame: "The window couldn't be placed inside the destination display's usable area."
            case .frameWriteFailed: "The app refused the window move or resize."
            case .timedOut: "macOS didn't confirm stable window placement on the destination display. Try again."
            }
        }
    }

    struct Client {
        var topology: () -> DisplayTopology
        var membership: () -> SpaceID?
        var frame: () -> CGRect?
        var serverFrame: () -> CGRect?
        var moveSpace: (SpaceID) async throws -> Void
        var writeFrame: (CGRect) -> Bool
        var wait: () async throws -> Void
    }

    static func move(to destination: DisplayTopology.Display, frame target: CGRect, client: Client) async throws {
        func validateDestination() throws {
            try Task.checkCancellation()
            guard destination.isEligible, client.topology().displays.contains(destination) else {
                throw MoveError.destinationChanged
            }
        }
        try validateDestination()
        guard target.size.width > 0, target.size.height > 0,
              [target.minX, target.minY, target.width, target.height].allSatisfy(\.isFinite),
              destination.usableFrame.contains(target) else { throw MoveError.invalidFrame }
        guard let space = destination.activeSpace?.id, let source = client.membership() else { throw MoveError.windowUnavailable }
        if source != space { try await client.moveSpace(space) }
        try validateDestination()
        guard client.membership() != nil else { throw MoveError.windowUnavailable }
        guard client.writeFrame(target) else { throw MoveError.frameWriteFailed }
        var stable = 0
        for _ in 0..<150 {
            try validateDestination()
            guard let current = client.membership() else { throw MoveError.windowUnavailable }
            let actual = client.frame(), server = client.serverFrame()
            let agrees = current == space && actual.map { matches($0, target) } == true
                && server.map { matches($0, target) } == true
                && actual.flatMap { client.topology().owner(of: $0)?.id } == destination.id
            stable = agrees ? stable + 1 : 0
            if stable == 5 { return }
            try await client.wait()
        }
        throw MoveError.timedOut
    }

    /// Preserve logical size and relative offset when possible; clamp/shrink only to fit usable bounds.
    static func floatingFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let width = min(frame.width, destination.width), height = min(frame.height, destination.height)
        let x = min(max(destination.minX + frame.minX - source.minX, destination.minX), destination.maxX - width)
        let y = min(max(destination.minY + frame.minY - source.minY, destination.minY), destination.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        // Allow native rounding to logical points, not a different minimum-size/clamped placement.
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}
