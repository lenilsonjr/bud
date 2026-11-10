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

    func testSwatchWritesItselfBackAsTheDesignFileDoes() {
        XCTAssertEqual(Swatch(hex: "#f7f9f3")?.hex, "#F7F9F3")
        XCTAssertEqual(Swatch(hex: "1B3A2417")?.hex, "#1B3A2417")
        XCTAssertEqual(Swatch(hex: "#FFFFFF00")?.hex, "#FFFFFF00", "Fully transparent still carries its alpha")
        XCTAssertEqual(Swatch(hex: "#85857FFF")?.hex, "#85857F", "An opaque alpha is dropped")
    }

    func testPaletteMatchesTheFoundationsBoard() {
        XCTAssertEqual(Palette.window, Tone("#F7F9F3", "#141414"))
        XCTAssertEqual(Palette.canvas, Tone("#EDF3E7", "#161616"))
        XCTAssertEqual(Palette.card, Tone("#CDE3C1", "#222222"))
        XCTAssertEqual(Palette.cardLit, Tone("#8CCC8C", "#5DBB68"))
        XCTAssertEqual(Palette.hub, Tone("#24432B", "#262626"), "The hub is green by day and graphite by night")
        XCTAssertEqual(Palette.text, Tone("#14281B", "#EDEDEB"))
        XCTAssertEqual(Palette.leaf, Tone("#3B7A45", "#7FCB86"))
        XCTAssertEqual(Palette.amethyst, Tone("#5B2A9E", "#C3B2EE"))
        XCTAssertEqual(Palette.rose, Tone("#A23A59", "#EC9BB4"))
        XCTAssertNotEqual(Palette.line.light, Palette.line.dark, "Dark mirrors every token with its own value")
    }

    func testEveryTokenIsInTheTableUnderItsBoardName() {
        XCTAssertEqual(Palette.tokens.count, 53)
        XCTAssertEqual(Palette.tokens["ui-window"], Palette.window)
        XCTAssertEqual(Palette.tokens["ui-text-3"], Palette.text3)
        XCTAssertEqual(Palette.tokens["ui-card-lit-ink"], Palette.cardLitInk)
        XCTAssertNil(Palette.tokens["ui-font"], "Only colours live in the table")
    }

    func testDarkModeIsGraphite() {
        let graphite = [
            "ui-window": "#141414", "ui-sidebar": "#141414", "ui-canvas": "#161616",
            "ui-surface": "#1A1A1A", "ui-raised": "#242424",
            "ui-line": "#FFFFFF14", "ui-line-strong": "#FFFFFF26",
            "ui-text": "#EDEDEB", "ui-text-2": "#B5B5B0", "ui-text-3": "#85857F",
            "ui-leaf": "#7FCB86", "ui-leaf-fill": "#5DBB68", "ui-on-leaf": "#0B160D",
            "ui-card": "#222222", "ui-card-line": "#343434",
            "ui-card-lit": "#5DBB68", "ui-card-lit-ink": "#0B160D",
            "ui-hub": "#262626", "ui-hub-line": "#3A3A3A",
        ]
        for (name, hex) in graphite {
            XCTAssertEqual(Palette.tokens[name]?.dark.hex, hex, name)
        }
    }

    func testDarkSurfacesLinesAndTextCarryNoGreen() throws {
        // Neutral means the three channels agree; a hair of warmth in the text is allowed, a
        // tint of green is not. Green stays on the leaf, the lit card and the hub's accent.
        let neutral = [
            "ui-window", "ui-sidebar", "ui-canvas", "ui-surface", "ui-raised", "ui-glass",
            "ui-line", "ui-line-strong", "ui-text", "ui-text-2", "ui-text-3",
            "ui-card", "ui-card-line", "ui-card-ink", "ui-card-meta",
            "ui-hub", "ui-hub-line", "ui-hub-ink", "ui-hub-meta",
        ]
        for name in neutral {
            let swatch = try XCTUnwrap(Palette.tokens[name]).dark
            XCTAssertLessThanOrEqual(swatch.green, max(swatch.red, swatch.blue) + 0.001, "\(name) leans green: \(swatch.hex)")
        }
        XCTAssertGreaterThan(Palette.leaf.dark.green, Palette.leaf.dark.red, "The leaf is still green")
        XCTAssertGreaterThan(Palette.cardLit.dark.green, Palette.cardLit.dark.red, "So is the lit card")
    }

    func testLuminanceAndContrastFollowWCAG() throws {
        let black = try XCTUnwrap(Swatch(hex: "#000000"))
        let white = try XCTUnwrap(Swatch(hex: "#FFFFFF"))
        XCTAssertEqual(black.luminance, 0)
        XCTAssertEqual(white.luminance, 1, accuracy: 0.0001)
        XCTAssertEqual(white.contrast(against: black), 21, accuracy: 0.0001)
        XCTAssertEqual(black.contrast(against: white), 21, accuracy: 0.0001, "The ratio does not care which is on top")
        let grey = try XCTUnwrap(Swatch(hex: "#777777"))
        XCTAssertEqual(grey.luminance, 0.1845, accuracy: 0.0005)
        XCTAssertEqual(white.contrast(against: grey), 4.48, accuracy: 0.01)
    }

    func testTheQuietestTextStillReadsOnEverySurfaceInTheDark() {
        XCTAssertGreaterThanOrEqual(Palette.text3.dark.contrast(against: Palette.surface.dark), 4.5)
        XCTAssertGreaterThanOrEqual(Palette.text3.dark.contrast(against: Palette.canvas.dark), 4.5)
        XCTAssertGreaterThanOrEqual(Palette.text3.dark.contrast(against: Palette.window.dark), 4.5)
        XCTAssertGreaterThanOrEqual(Palette.text.dark.contrast(against: Palette.surface.dark), 7)
        XCTAssertGreaterThanOrEqual(Palette.onLeaf.dark.contrast(against: Palette.leafFill.dark), 4.5)
        XCTAssertGreaterThanOrEqual(Palette.cardLitInk.dark.contrast(against: Palette.cardLit.dark), 4.5)
    }

    func testRadiiFollowTheBoard() {
        XCTAssertEqual(Radius.sm, 6)
        XCTAssertEqual(Radius.md, 10)
        XCTAssertEqual(Radius.lg, 14)
        XCTAssertEqual(Radius.xl, 22)
        XCTAssertEqual(Radius.keycap, 4)
        XCTAssertEqual(Radius.chip, 5)
        XCTAssertEqual(Radius.iconButton, 7)
        XCTAssertEqual(Radius.button, 8)
        XCTAssertEqual(Radius.field, 8)
        XCTAssertEqual(Radius.segmented, 9)
        XCTAssertEqual(Radius.card, 10)
        XCTAssertEqual(Radius.toast, 12)
        XCTAssertEqual(Radius.detail, 14)
        XCTAssertEqual(Radius.hub, 20)
        XCTAssertEqual(Radius.sheet, 22)
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
