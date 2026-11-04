import XCTest
@testable import BudKit
#if canImport(CoreImage)
import CoreImage
#endif

final class QRModulesTests: XCTestCase {
    func testTrimmingDropsTheLightBorder() {
        let grid = [
            [false, false, false, false],
            [false, true, false, false],
            [false, false, true, false],
            [false, false, false, false],
        ]
        XCTAssertEqual(QRModules.trimmed(grid), [[true, false], [false, true]])
        XCTAssertNil(QRModules.trimmed([[false, false], [false, false]]))
    }

    #if canImport(CoreImage)
    func testATicketEncodesToACodeACameraCanRead() throws {
        let text = "bud1k7f3a91c4z2m9q0e8r6t5y3u1i7o9p2s4d6f8g0h"
        let modules = try XCTUnwrap(QRModules.encode(text))
        XCTAssertEqual(modules.count, modules.first?.count, "A QR code is square")
        XCTAssertEqual((modules.count - 21) % 4, 0, "A QR code has 21 + 4k modules a side")
        // The finder square in the top-left corner: a dark ring seven modules wide.
        XCTAssertTrue((0..<7).allSatisfy { modules[0][$0] && modules[6][$0] && modules[$0][0] && modules[$0][6] })
        XCTAssertEqual(try decode(modules), text)
    }

    func testTheStandInDrawsItsTicketAsARealCode() async throws {
        let ticket = try await MemoryPeers().ticket(withAddresses: false)
        XCTAssertEqual(try decode(ticket.qr), ticket.text)
    }

    /// Draws the modules ten pixels each with a four-module margin and reads them back.
    private func decode(_ modules: [[Bool]]) throws -> String? {
        let scale = 10
        let margin = 4
        let side = (modules.count + margin * 2) * scale
        var pixels = [UInt8](repeating: 255, count: side * side)
        for (row, line) in modules.enumerated() {
            for (column, dark) in line.enumerated() where dark {
                for y in 0..<scale {
                    for x in 0..<scale {
                        pixels[((row + margin) * scale + y) * side + (column + margin) * scale + x] = 0
                    }
                }
            }
        }
        let image = CIImage(
            bitmapData: Data(pixels), bytesPerRow: side, size: CGSize(width: side, height: side),
            format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        return (detector.features(in: image).first as? CIQRCodeFeature)?.messageString
    }
    #endif
}
