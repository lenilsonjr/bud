#if os(macOS)
import SwiftUI
import BudKit

/// The Commands menu: every row of the table under its scope, with the key it answers to now,
/// so the system lists them and System Settings › Keyboard can rebind each by name. A bare key
/// (N, Space, Esc, an arrow) is a letter in any text field, so only a modified key stands as a
/// menu key equivalent; the rest are named alone and run from the menu. A row outside its scope
/// is greyed out. A key recorded on the sheet reaches here through the store, which passes the
/// layout's changes on as its own.
struct BudCommands: Commands {
    @ObservedObject var store: BudStore

    var body: some Commands {
        CommandMenu("Commands") {
            ForEach(Command.menuScopes, id: \.self) { scope in
                Section(scope.rawValue) {
                    ForEach(Command.menu(in: scope)) { command in
                        item(command)
                    }
                }
            }
        }
    }

    /// A row's item, with its key when a modified one, and with none while the sheet records a
    /// key: a menu key equivalent, greyed out or not, is answered before any view hears it.
    private func item(_ command: Command) -> some View {
        let key = Keys.key(for: command.id)
        return Button(command.name) { store.perform(command.id) }
            .disabled(!store.allows(command.id))
            .keyboardShortcut(key.hasModifiers && Keys.layout.recording == nil ? key.shortcut : nil)
    }
}
#endif
