#if canImport(SwiftUI) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO

/// A card's picture as the page draws it: decoded once, no larger than the card's slot at two
/// pixels a point, and kept on the store by the bud's id. The vault's index says which picture a
/// bud embeds first; nothing here reads a body.
public struct BoardPicture: @unchecked Sendable {
    public let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    /// The widest a card's picture is drawn, in pixels: 248 pt at two pixels a point.
    public static let maxPixels = 496

    /// Decodes picture bytes to at most `maxPixels` on the longer side, turned the way the file
    /// says; nil for bytes that are not a picture.
    public static func decode(_ data: Data, maxPixels: Int = maxPixels) -> BoardPicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return BoardPicture(image: image)
    }
}

/// What the store knows of a bud's picture: nothing asked yet, none, or the picture.
public enum BoardPictureState: Sendable {
    case unknown
    case none
    case picture(BoardPicture)

    public var picture: BoardPicture? {
        if case .picture(let picture) = self { return picture }
        return nil
    }
}

#endif
