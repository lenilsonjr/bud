import XCTest
@testable import BudKit

final class ThemeTests: XCTestCase {
    func testSwatchParsesSixAndEightDigitHex() throws {
        let opaque = try XCTUnwrap(Swatch(hex: "#F7F9F3"))
        XCTAssertEqual(opaque.red, 0xF7 / 255, accuracy: 0.0001)
        XCTAssertEqual(opaque.green, 0xF9 / 255, accuracy: 0.0001)
        XCTAssertEqual(opaque.blue, 0xF3 / 255, accuracy: 0.0001)
        XCTAssertEqual(opaque.alpha, 1)

        let translucent = try XCTUnwrap(Swatch(hex: "1B3A2417"))
        XCTAssertEqual(translucent.alpha, 0x17 / 255, accuracy: 0.0001)

        XCTAssertNil(Swatch(hex: "#FFF"))
        XCTAssertNil(Swatch(hex: "#GGGGGG"))
    }

    func testPaletteMatchesTheFoundationsBoard() {
        XCTAssertEqual(Palette.window, Tone("#F7F9F3", "#0C140F"))
        XCTAssertEqual(Palette.canvas, Tone("#EDF3E7", "#0F1912"))
        XCTAssertEqual(Palette.card, Tone("#CDE3C1", "#21392A"))
        XCTAssertEqual(Palette.cardLit, Tone("#8CCC8C", "#8CCC8C"))
        XCTAssertEqual(Palette.hub, Tone("#24432B", "#24432B"))
        XCTAssertEqual(Palette.text, Tone("#14281B", "#EEF5EA"))
        XCTAssertEqual(Palette.leaf, Tone("#3B7A45", "#8CCC8C"))
        XCTAssertEqual(Palette.amethyst, Tone("#5B2A9E", "#C3B2EE"))
        XCTAssertEqual(Palette.rose, Tone("#A23A59", "#EC9BB4"))
        XCTAssertNotEqual(Palette.line.light, Palette.line.dark, "Dark mirrors every token with its own value")
    }

    func testRadiiFollowTheBoard() {
        XCTAssertEqual(Radius.sm, 6)
        XCTAssertEqual(Radius.md, 10)
        XCTAssertEqual(Radius.lg, 14)
        XCTAssertEqual(Radius.xl, 22)
    }

    func testTypeScaleFollowsTheBoard() {
        XCTAssertEqual(TextRole.display.style, TextStyle(typeface: .display, size: 34, weight: 500))
        XCTAssertEqual(TextRole.title.style, TextStyle(typeface: .display, size: 26, weight: 500))
        XCTAssertEqual(TextRole.heading.style, TextStyle(typeface: .text, size: 17, weight: 600))
        XCTAssertEqual(TextRole.body.style, TextStyle(typeface: .text, size: 14, weight: 400))
        XCTAssertEqual(TextRole.cardTitle.style, TextStyle(typeface: .text, size: 13, weight: 600))
        XCTAssertEqual(TextRole.label.style, TextStyle(typeface: .text, size: 12, weight: 500))
        XCTAssertEqual(TextRole.caption.style, TextStyle(typeface: .text, size: 11, weight: 400))
        XCTAssertEqual(TextRole.eyebrow.style, TextStyle(typeface: .text, size: 10, weight: 700, tracking: 1.6, uppercase: true))
        XCTAssertEqual(TextRole.mono.style, TextStyle(typeface: .mono, size: 12, weight: 400))
    }

    func testFontFilesAreBundled() throws {
        for face in Typeface.allCases {
            let url = try XCTUnwrap(face.url, "\(face.family) is missing from the package resources")
            let size = try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            XCTAssertGreaterThan(size, 10_000, "\(face.file) looks truncated")
        }
    }
}
