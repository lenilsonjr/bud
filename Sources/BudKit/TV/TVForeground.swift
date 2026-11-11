import Foundation

/// Tells a return from the background apart from the TV only stepping aside. A system overlay,
/// such as Control Center or a notification, takes the app from active to inactive and back
/// without leaving it; only a trip through the background means the TV was away long enough
/// for the peers to have moved on, and asks for a sync. Kept apart from the view so it tests on
/// its own.
public struct TVForeground: Equatable, Sendable {
    /// Where the app is, as the scene tells it.
    public enum Phase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    private var away = false
    private var phase = Phase.active

    public init() {}

    /// Notes that the app moved to `phase`. True when it is active again after the background,
    /// once for each trip. While not `syncing`, as on the launch fetch, the trip is held for
    /// `resume` rather than lost.
    public mutating func moved(to phase: Phase, syncing: Bool = true) -> Bool {
        self.phase = phase
        switch phase {
        case .background:
            away = true
            return false
        case .inactive:
            return false
        case .active:
            guard syncing, away else { return false }
            away = false
            return true
        }
    }

    /// Syncing can start again, as when the launch fetch is over. True, once, when a trip
    /// through the background came while it waited and the app is active now; still away, the
    /// return itself syncs.
    public mutating func resume() -> Bool {
        guard away, phase == .active else { return false }
        away = false
        return true
    }
}
