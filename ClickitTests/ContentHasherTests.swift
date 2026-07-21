import XCTest
@testable import Clickit

final class ContentHasherTests: XCTestCase {
    func testIdenticalTextProducesIdenticalHash() {
        XCTAssertEqual(
            ContentHasher.hash(text: "hello world", type: .text),
            ContentHasher.hash(text: "hello world", type: .text)
        )
    }

    func testDifferentTextProducesDifferentHash() {
        XCTAssertNotEqual(
            ContentHasher.hash(text: "hello world", type: .text),
            ContentHasher.hash(text: "hello worlds", type: .text)
        )
    }

    /// The same string captured as text and as a URL must stay two entries.
    func testSameContentUnderDifferentTypesDoesNotCollide() {
        let string = "https://example.com"
        XCTAssertNotEqual(
            ContentHasher.hash(text: string, type: .text),
            ContentHasher.hash(text: string, type: .url)
        )
    }

    func testHashIsCaseSensitiveAndWhitespaceSensitive() {
        XCTAssertNotEqual(
            ContentHasher.hash(text: "Token", type: .text),
            ContentHasher.hash(text: "token", type: .text)
        )
        XCTAssertNotEqual(
            ContentHasher.hash(text: "token", type: .text),
            ContentHasher.hash(text: "token ", type: .text)
        )
    }

    func testImageDataHashing() {
        let first = Data([0x01, 0x02, 0x03])
        let second = Data([0x01, 0x02, 0x04])
        XCTAssertEqual(
            ContentHasher.hash(data: first, type: .image),
            ContentHasher.hash(data: first, type: .image)
        )
        XCTAssertNotEqual(
            ContentHasher.hash(data: first, type: .image),
            ContentHasher.hash(data: second, type: .image)
        )
    }

    func testHashIsHexEncodedSHA256() {
        let hash = ContentHasher.hash(text: "anything", type: .text)
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}
