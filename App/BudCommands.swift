#if os(macOS)
import SwiftUI
import BudKit

/// The Commands menu: every row of the table under its scope, with the key it answers to, so
/// the system lists them and System Settings › Keyboard can rebind each by name. A bare key (N,
/// Space, Esc, an arrow) is a letter in any text field, so only a modified key stands as a menu
/// key equivalent; the rest are named alone and run from the menu. A row outside its scope is
/// greyed out.
struct BudCommands: Commands {
    @ObservedObject var store: BudStore

    var body: some Commands {
        CommandMenu("Commands") {
            ForEach(Command.Scope.allCases, id: \.self) { scope in
                Section(scope.rawValue) {
                    ForEach(Command.menu(in: scope)) { command in
                        item(command)
                    }
                }
            }
        }
    }

    @ViewBuilder private func item(_ command: Command) -> some View {
        let button = Button(command.name) { store.perform(command.id) }
            .disabled(!store.allows(command.id))
        if command.key.hasModifiers {
            button.keyboardShortcut(command.key.shortcut)
        } else {
            button
        }
    }
}
#endif
