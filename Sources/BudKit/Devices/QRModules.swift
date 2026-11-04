import Foundation
#if canImport(CoreImage)
import CoreImage
#endif

/// The modules of a real QR code for a line of text, `true` is dark, with no quiet zone: the tile
/// draws its own margin. Nil where the system has no QR generator.
public enum QRModules {
    public static func encode(_ text: String) -> [[Bool]]? {
        #if canImport(CoreImage)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(
            image, toBitmap: &pixels, rowBytes: width * 4,
            bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // One pixel per module; the first row of the bitmap is the top of the code.
        let grid = (0..<height).map { row in
            (0..<width).map { column in pixels[(row * width + column) * 4] < 128 }
        }
        return trimmed(grid)
        #else
        return nil
        #endif
    }

    /// The grid without the light rows and columns around it.
    static func trimmed(_ grid: [[Bool]]) -> [[Bool]]? {
        let rows = grid.indices.filter { grid[$0].contains(true) }
        guard let top = rows.first, let bottom = rows.last else { return nil }
        let columns = (0..<(grid.first?.count ?? 0)).filter { column in grid.contains { $0[column] } }
        guard let left = columns.first, let right = columns.last else { return nil }
        return (top...bottom).map { Array(grid[$0][left...right]) }
    }
}
