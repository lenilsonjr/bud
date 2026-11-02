import Foundation

/// What the top bar says about sync, read from the node's state: nothing when quiet, a dot when
/// a device is connected, a count when changes wait to go out (hollow when nobody is connected),
/// and a brief mark while a sync runs.
public enum SyncIndicator: Hashable, Sendable {
    case quiet
    case connected(devices: Int)
    case pending(changes: Int, devices: Int)
    case pendingApart(changes: Int)
    case syncing(devices: Int)

    public init(_ state: SyncState?) {
        guard let state else {
            self = .quiet
            return
        }
        if !state.idle {
            self = .syncing(devices: state.connectedPeers)
        } else if state.pendingChanges > 0 {
            self = state.connectedPeers > 0
                ? .pending(changes: state.pendingChanges, devices: state.connectedPeers)
                : .pendingApart(changes: state.pendingChanges)
        } else if state.connectedPeers > 0 {
            self = .connected(devices: state.connectedPeers)
        } else {
            self = .quiet
        }
    }

    /// Whether the bar shows anything at all.
    public var isShown: Bool { self != .quiet }

    /// The changes waiting to go out, shown as the count beside the dot.
    public var count: Int? {
        switch self {
        case let .pending(changes, _), let .pendingApart(changes): return changes
        default: return nil
        }
    }

    /// Whether the dot is drawn hollow: changes wait but nobody is connected to take them.
    public var isHollow: Bool {
        if case .pendingApart = self { return true }
        return false
    }

    /// What hovering or VoiceOver reads out.
    public var label: String {
        switch self {
        case .quiet:
            return ""
        case let .connected(devices):
            return Self.devicesConnected(devices)
        case let .pending(changes, devices):
            return "\(Self.devicesConnected(devices)) · \(Self.changesWaiting(changes))"
        case let .pendingApart(changes):
            return "\(Self.changesWaiting(changes)) · no device connected"
        case let .syncing(devices):
            return devices > 0 ? "Syncing with \(Self.devices(devices))" : "Syncing"
        }
    }

    static func devices(_ count: Int) -> String { count == 1 ? "1 device" : "\(count) devices" }

    static func devicesConnected(_ count: Int) -> String { "\(devices(count)) connected" }

    static func changesWaiting(_ count: Int) -> String {
        count == 1 ? "1 change waiting to go out" : "\(count) changes waiting to go out"
    }
}

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Sync dot of the board: a 26 pt pill with an 8 pt leaf dot, a count when changes wait,
/// hollow when nobody is connected, and a soft fill with the cycle mark while a sync runs.
struct SyncDot: View {
    @ObservedObject var devices: DeviceStore

    var body: some View {
        let indicator = SyncIndicator(devices.syncState)
        if indicator.isShown {
            HStack(spacing: 6) {
                dot(hollow: indicator.isHollow)
                if case .syncing = indicator {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text2)
                }
                if let count = indicator.count {
                    Text("\(count)")
                        .textRole(.label)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text2)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(fill(indicator), in: Capsule())
            .overlay(Capsule().stroke(indicator.count != nil ? Theme.line : .clear, lineWidth: 1))
            .help(indicator.label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(indicator.label)
        }
    }

    private func dot(hollow: Bool) -> some View {
        Circle()
            .fill(hollow ? Color.clear : Theme.leaf)
            .overlay(Circle().stroke(Theme.leaf, lineWidth: hollow ? 1.5 : 0))
            .frame(width: 8, height: 8)
    }

    private func fill(_ indicator: SyncIndicator) -> Color {
        switch indicator {
        case .syncing: return Theme.leafSoft
        case .pending, .pendingApart: return Theme.sidebar
        default: return .clear
        }
    }
}

/// The same states riding on the gear on iPhone and iPad: a dot at its corner, with the count
/// when changes wait, so Canvas and Files stay centred and the tap already leads to Devices.
struct SyncBadge: View {
    @ObservedObject var devices: DeviceStore

    var body: some View {
        let indicator = SyncIndicator(devices.syncState)
        if indicator.isShown {
            Group {
                if let count = indicator.count {
                    Text("\(count)")
                        .font(Theme.font(TextStyle(typeface: .text, size: 9, weight: 600)))
                        .monospacedDigit()
                        .foregroundStyle(indicator.isHollow ? Theme.leaf : Theme.hubInk)
                        .padding(.horizontal, 4)
                        .frame(height: 14)
                        .background(indicator.isHollow ? Theme.window : Theme.leaf, in: Capsule())
                        .overlay(Capsule().stroke(Theme.leaf, lineWidth: indicator.isHollow ? 1.5 : 0))
                } else {
                    Circle()
                        .fill(Theme.leaf)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.window, lineWidth: 1.5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(indicator.label)
        }
    }
}
#endif
