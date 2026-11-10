#if canImport(Combine)
import Foundation
import Combine

/// The one toast at the bottom: the latest undoable action, shown for a few seconds, gone on
/// Undo or when the next one arrives.
@MainActor
public final class ToastCenter: ObservableObject {
    public struct Toast: Identifiable {
        public let id = UUID()
        public let action: Undoable
    }

    @Published public private(set) var current: Toast?
    private let duration: Duration
    private var timer: Task<Void, Never>?

    public init(duration: Duration = .seconds(4)) {
        self.duration = duration
    }

    public func show(_ action: Undoable) {
        timer?.cancel()
        let toast = Toast(action: action)
        current = toast
        timer = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    /// Runs the current action's undo and drops the toast; a toast that only reports stays.
    public func undo() {
        guard let toast = current, let undo = toast.action.undo else { return }
        timer?.cancel()
        current = nil
        undo()
    }

    public func dismiss(_ id: UUID? = nil) {
        guard let toast = current, id == nil || id == toast.id else { return }
        timer?.cancel()
        current = nil
    }
}
#endif

#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The toast as the board draws it: a mark when it has one, one line and Undo when the action can
/// be taken back, raised above the bottom edge.
struct ToastView: View {
    @ObservedObject var center: ToastCenter
    /// Undo's key is the recorder's while the shortcuts sheet records one.
    @ObservedObject private var keys = Keys.layout

    var body: some View {
        if let toast = center.current {
            HStack(spacing: 14) {
                if let symbol = toast.action.systemImage {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Theme.hubAccent)
                        .padding(.trailing, -4)
                }
                Text(toast.action.message)
                    .textRole(.body)
                    .foregroundStyle(Theme.hubInk)
                if toast.action.undo != nil {
                    Button("Undo") { center.undo() }
                        .buttonStyle(.plain)
                        .textRole(.label)
                        .foregroundStyle(Theme.hubAccent)
                        .keyboardShortcut(Keys.shortcut(.undo))
                        .disabled(keys.recording != nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.hub, in: RoundedRectangle(cornerRadius: Radius.toast, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.toast, style: .continuous).stroke(Theme.hubLine, lineWidth: 1))
            .shadow(color: Theme.shadowStrong, radius: 12, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }
}
#endif
