import Foundation
import IOKit.pwr_mgt

enum PowerAssertionKind: String, CaseIterable {
    case system = "PreventUserIdleSystemSleep"
    case display = "PreventUserIdleDisplaySleep"

    static func required(for mode: KeepAwakeMode) -> Set<Self> {
        mode == .system ? [.system] : [.system, .display]
    }
}

protocol PowerAssertionClient {
    func create(_ kind: PowerAssertionKind) throws -> IOPMAssertionID
    func release(_ id: IOPMAssertionID) throws
}

struct PowerAssertionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct NativePowerAssertionClient: PowerAssertionClient {
    func create(_ kind: PowerAssertionKind) throws -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Momentum Keep Awake — \(kind == .system ? "System" : "Display")" as CFString, &id)
        guard result == kIOReturnSuccess, id != 0 else {
            throw PowerAssertionError(message: "Couldn't request \(kind.rawValue) (IOKit \(result)).")
        }
        return id
    }

    func release(_ id: IOPMAssertionID) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError(message: "Couldn't release Keep Awake assertion \(id) (IOKit \(result)).")
        }
    }
}

/// Owns only Momentum's IDs. Preparation adds protection without removing the working mode.
final class PowerAssertions {
    private let client: any PowerAssertionClient
    private(set) var owned: [PowerAssertionKind: IOPMAssertionID] = [:]
    private(set) var pendingCleanup: Set<IOPMAssertionID> = []
    private(set) var cleanupError: String?

    init(client: any PowerAssertionClient = NativePowerAssertionClient()) {
        self.client = client
    }

    func prepare(_ mode: KeepAwakeMode) throws -> [PowerAssertionKind: IOPMAssertionID] {
        // Unresolved rollback must not be lost or silently reused as current protection.
        retryCleanup()
        guard pendingCleanup.isEmpty else {
            throw PowerAssertionError(message: cleanupError ?? "Keep Awake cleanup is pending.")
        }
        var additions: [PowerAssertionKind: IOPMAssertionID] = [:]
        do {
            for kind in PowerAssertionKind.allCases where PowerAssertionKind.required(for: mode).contains(kind) && owned[kind] == nil {
                let id = try client.create(kind)
                guard id != 0 else { throw PowerAssertionError(message: "IOKit returned an invalid assertion ID.") }
                additions[kind] = id
            }
            return additions
        } catch {
            rollback(additions)
            throw PowerAssertionError(message: [error.localizedDescription, cleanupError].compactMap { $0 }.joined(separator: " "))
        }
    }

    func commit(_ additions: [PowerAssertionKind: IOPMAssertionID], mode: KeepAwakeMode) throws {
        // The only removal is display protection on downgrade. Keep it part of the
        // working mode until release succeeds; cleanup Retry must not release it.
        if mode == .system, let id = owned[.display] {
            try releaseWithRetry(id)
            owned.removeValue(forKey: .display)
        }
        owned.merge(additions) { old, _ in old }
    }

    func rollback(_ additions: [PowerAssertionKind: IOPMAssertionID]) {
        pendingCleanup.formUnion(additions.values)
        retryCleanup()
    }

    func releaseAll() {
        pendingCleanup.formUnion(owned.values)
        owned.removeAll()
        retryCleanup()
    }

    /// At most two attempts per ID per cleanup command; no main-thread retry loop.
    func retryCleanup() {
        cleanupError = nil
        for id in pendingCleanup.sorted() {
            do {
                try releaseWithRetry(id)
                pendingCleanup.remove(id)
            } catch { cleanupError = error.localizedDescription }
        }
        if pendingCleanup.isEmpty { cleanupError = nil }
    }

    private func releaseWithRetry(_ id: IOPMAssertionID) throws {
        do { try client.release(id) }
        catch { try client.release(id) }
    }
}
