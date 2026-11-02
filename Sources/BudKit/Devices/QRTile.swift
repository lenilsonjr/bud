import Foundation

/// Where the modules of a QR code sit inside the tile: the board draws a 184 pt code inside a
/// 216 pt tile, and the same share of a bigger tile on the TV.
public struct QRLayout: Hashable, Sendable {
    public static let codeShare: Double = 184.0 / 216.0

    public let size: Double
    public let modules: Int

    public init(size: Double = 216, modules: Int) {
        self.size = size
        self.modules = max(1, modules)
    }

    /// The side of the code itself.
    public var code: Double { size * Self.codeShare }

    /// The margin between the tile's edge and the code.
    public var inset: Double { (size - code) / 2 }

    /// The side of one module.
    public var module: Double { code / Double(modules) }

    /// The square of one module as (x, y, side), with the origin at the tile's corner.
    public func square(row: Int, column: Int) -> (x: Double, y: Double, side: Double) {
        (inset + Double(column) * module, inset + Double(row) * module, module)
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The QR tile of the board: hub ink behind, the code in hub green, a hairline around; when the
/// ticket has run out a veil with "Expired" lies over the code.
struct QRTile: View {
    let modules: [[Bool]]
    var size: CGFloat = 216
    var corner: CGFloat = Radius.detail
    var expired = false

    var body: some View {
        let layout = QRLayout(size: size, modules: modules.count)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Canvas { context, _ in
            for (row, line) in modules.enumerated() {
                for (column, dark) in line.enumerated() where dark {
                    let square = layout.square(row: row, column: column)
                    context.fill(Path(CGRect(x: square.x, y: square.y, width: square.side, height: square.side)), with: .color(Theme.hub))
                }
            }
        }
        .frame(width: size, height: size)
        .background(Theme.hubInk, in: shape)
        .overlay(shape.stroke(Theme.lineStrong, lineWidth: 1))
        .overlay {
            if expired {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.hub)
                    Text("Expired")
                        .font(Theme.font(TextStyle(typeface: .text, size: 13, weight: 500)))
                        .foregroundStyle(Theme.hub)
                }
                .frame(width: size, height: size)
                .background(Theme.hubInk.opacity(0.7), in: shape)
            }
        }
        .accessibilityLabel(expired ? "Expired ticket" : "Ticket code")
    }
}
#endif
