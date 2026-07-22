import AppKit
import XCTest
@testable import Clickit

/// The point of the thumbnail path is that a large screenshot never decodes at
/// full size. These tests pin that: a big source yields a small-pixel thumbnail,
/// and a file that is not an image fails cleanly instead of returning garbage.
final class ThumbnailDownsamplingTests: XCTestCase {
    func testDownsamplesLargeImageToTheRequestedMaxPixelSize() throws {
        let url = try writePNG(side: 2_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try XCTUnwrap(ImageDownsampler.thumbnail(fileURL: url, maxPixelSize: 96))

        XCTAssertGreaterThan(thumbnail.width, 0)
        XCTAssertLessThanOrEqual(thumbnail.width, 96)
        XCTAssertLessThanOrEqual(thumbnail.height, 96)
        // A 2000×2000 source must not survive anywhere near full size: the whole
        // reason this exists is that the decoded bitmap stays tiny.
        XCTAssertLessThan(thumbnail.width * thumbnail.height, 2_000 * 2_000 / 100)
    }

    func testReturnsNilForAFileThatIsNotAnImage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-image-\(UUID().uuidString).png")
        try Data("plainly not a PNG".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(ImageDownsampler.thumbnail(fileURL: url, maxPixelSize: 96))
    }

    func testReturnsNilForAMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).png")

        XCTAssertNil(ImageDownsampler.thumbnail(fileURL: url, maxPixelSize: 96))
    }

    /// Writes a real square PNG to a scratch file.
    private func writePNG(side: Int) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-source-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
