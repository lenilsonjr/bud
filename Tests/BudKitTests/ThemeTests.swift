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
        XCTAssertNil(Swatch(hex: "#+1A2B3"), "A sign is not a digit, whatever the integer parser thinks")
        XCTAssertNil(Swatch(hex: "-1A2B3C"))
    }

    func testSwatchWritesItselfBackAsTheDesignFileDoes() {
        XCTAssertEqual(Swatch(hex: "#f7f9f3")?.hex, "#F7F9F3")
        XCTAssertEqual(Swatch(hex: "1B3A2417")?.hex, "#1B3A2417")
        XCTAssertEqual(Swatch(hex: "#FFFFFF00")?.hex, "#FFFFFF00", "Fully transparent still carries its alpha")
        XCTAssertEqual(Swatch(hex: "#85857FFF")?.hex, "#85857F", "An opaque alpha is dropped")
    }

    func testPaletteMatchesTheFoundationsBoardByDayAndGraphiteByNight() {
        // Every row of the board's table, light then dark, as the design file states it.
        let board = [
            "ui-amethyst": ("#5B2A9E", "#C3B2EE"),
            "ui-amethyst-soft": ("#5B2A9E14", "#B9A6E61F"),
            "ui-brand": ("#5B2A9E", "#5B2A9E"),
            "ui-canvas": ("#EDF3E7", "#161616"),
            "ui-card": ("#CDE3C1", "#222222"),
            "ui-card-agent": ("#E3D9F6", "#2B2445"),
            "ui-card-agent-ink": ("#3E1C70", "#DCCFF7"),
            "ui-card-agent-line": ("#BDABE7", "#5F4D96"),
            "ui-card-ink": ("#14281B", "#EDEDEB"),
            "ui-card-line": ("#8FB882", "#343434"),
            "ui-card-lit": ("#8CCC8C", "#5DBB68"),
            "ui-card-lit-ink": ("#0E1C13", "#0B160D"),
            "ui-card-lit-line": ("#4E8A55", "#9BDDA1"),
            "ui-card-lit-meta": ("#24432B", "#1F3A23"),
            "ui-card-meta": ("#4B6650", "#9A9A94"),
            "ui-card-note": ("#E3E8C0", "#25241F"),
            "ui-card-note-line": ("#B4BF79", "#3B3930"),
            "ui-card-note-meta": ("#626A3C", "#A8A48F"),
            "ui-glass": ("#FFFFFFE0", "#1C1C1CE6"),
            "ui-glow": ("#8CCC8C59", "#7FCB8626"),
            "ui-hub": ("#24432B", "#262626"),
            "ui-hub-accent": ("#8CCC8C", "#8CCC8C"),
            "ui-hub-ink": ("#EEF6EA", "#F2F2F0"),
            "ui-hub-line": ("#24432B", "#3A3A3A"),
            "ui-hub-mark": ("#B9A6E6", "#B9A6E6"),
            "ui-hub-meta": ("#A9C7A3", "#A0A09A"),
            "ui-kraft": ("#F6EFDF", "#1F1D18"),
            "ui-kraft-ink": ("#86652A", "#D9B877"),
            "ui-leaf": ("#3B7A45", "#7FCB86"),
            "ui-leaf-fill": ("#3F7F48", "#5DBB68"),
            "ui-leaf-glow": ("#8CCC8C40", "#7FCB861F"),
            "ui-leaf-line": ("#4E8A5580", "#7FCB8666"),
            "ui-leaf-soft": ("#4E8A551C", "#7FCB861F"),
            "ui-light": ("#FFFFFFB3", "#FFFFFF0A"),
            "ui-light-0": ("#FFFFFF00", "#FFFFFF00"),
            "ui-line": ("#1B3A2417", "#FFFFFF14"),
            "ui-line-strong": ("#1B3A2430", "#FFFFFF26"),
            "ui-lit": ("#DCEED3", "#1F2A21"),
            "ui-on-leaf": ("#FFFFFF", "#0B160D"),
            "ui-pistil": ("#7A4E12", "#EFC77F"),
            "ui-pistil-soft": ("#DCAC6240", "#DCAC6238"),
            "ui-raised": ("#FFFFFF", "#242424"),
            "ui-rose": ("#A23A59", "#EC9BB4"),
            "ui-rose-soft": ("#DF96B53D", "#E58AA626"),
            "ui-scrim": ("#1B2E2138", "#000000A6"),
            "ui-shadow": ("#1B2E211A", "#00000066"),
            "ui-shadow-strong": ("#1B2E2133", "#000000A6"),
            "ui-sidebar": ("#E8EFE2", "#141414"),
            "ui-surface": ("#FFFFFF", "#1A1A1A"),
            "ui-text": ("#14281B", "#EDEDEB"),
            "ui-text-2": ("#435848", "#B5B5B0"),
            "ui-text-3": ("#6C7F6E", "#85857F"),
            "ui-window": ("#F7F9F3", "#141414"),
        ]
        XCTAssertEqual(Palette.tokens.count, board.count, "The table has exactly the board's tokens")
        for (name, (light, dark)) in board {
            XCTAssertEqual(Palette.tokens[name]?.light.hex, light, "\(name) by day")
            XCTAssertEqual(Palette.tokens[name]?.dark.hex, dark, "\(name) by night")
        }
        XCTAssertEqual(Palette.window, Palette.tokens["ui-window"], "The statics read the table")
        XCTAssertEqual(Palette.cardLitInk, Palette.tokens["ui-card-lit-ink"])
        XCTAssertNil(Palette.tokens["ui-font"], "Only colours live in the table")
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

    func testATranslucentColourIsJudgedOverItsBackdrop() throws {
        let line = Palette.line.dark, surface = Palette.surface.dark
        XCTAssertEqual(line.over(surface).alpha, 1)
        XCTAssertEqual(line.over(surface).hex, "#2C2C2C", "A hairline of white over graphite is a slightly lighter graphite")
        XCTAssertLessThan(line.contrast(against: surface), 1.5, "Not the 17:1 the bare white would give")
        XCTAssertEqual(try XCTUnwrap(Swatch(hex: "#FF000000")).over(surface), surface, "Fully transparent changes nothing")
        XCTAssertEqual(try XCTUnwrap(Swatch(hex: "#FFFFFF")).over(surface).hex, "#FFFFFF", "Opaque covers it")
    }

    func testTheQuietestTextReadsOnTheWindowCanvasAndSurfaceInTheDark() {
        // Raised panels and cards sit a step lighter and fall just short of 4.5 with text-3;
        // that is the designer's to settle, so this test holds only what the board reaches.
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
