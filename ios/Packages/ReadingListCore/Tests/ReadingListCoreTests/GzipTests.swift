import XCTest
@testable import ReadingListCore

final class GzipTests: XCTestCase {

    func testRoundTrip() throws {
        let original = "Hello, gzip! 🎉".data(using: .utf8)!
        let compressed = try Gzip.compress(original)
        XCTAssertNotEqual(compressed, original)
        let decompressed = try Gzip.decompress(compressed)
        XCTAssertEqual(decompressed, original)
    }

    func testRoundTripEmptyData() throws {
        let compressed = try Gzip.compress(Data())
        let decompressed = try Gzip.decompress(compressed)
        XCTAssertEqual(decompressed, Data())
    }

    func testRoundTripLargeData() throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(500_000)
        for i in 0..<500_000 { bytes.append(UInt8(i % 251)) }
        let original = Data(bytes)
        let compressed = try Gzip.compress(original)
        let decompressed = try Gzip.decompress(compressed, maxOutput: 1_000_000)
        XCTAssertEqual(decompressed, original)
    }

    func testDecompressRejectsGarbage() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        XCTAssertThrowsError(try Gzip.decompress(garbage))
    }

    func testDecompressRejectsTruncatedStream() throws {
        let original = String(repeating: "abcdefgh", count: 1000).data(using: .utf8)!
        let compressed = try Gzip.compress(original)
        let truncated = compressed.prefix(compressed.count - 4)
        XCTAssertThrowsError(try Gzip.decompress(Data(truncated)))
    }

    func testDecompressEnforcesMaxOutput() throws {
        let original = Data(repeating: 0x41, count: 200_000) // highly compressible
        let compressed = try Gzip.compress(original)
        XCTAssertThrowsError(try Gzip.decompress(compressed, maxOutput: 1000)) { error in
            XCTAssertEqual(error as? GzipError, .outputTooLarge)
        }
    }

    /// Interop: this fixture was produced by Python's `gzip` module (a non-zlib-Swift
    /// producer), proving Gzip.decompress reads gzip streams from any conforming writer,
    /// the same way it must read a share link gzipped by a browser's CompressionStream.
    func testDecompressInteropWithPythonFixture() throws {
        guard let b64URL = Bundle.module.url(forResource: "gzip_fixture.b64", withExtension: "txt", subdirectory: "Fixtures"),
              let expectedJSONURL = Bundle.module.url(forResource: "gzip_fixture", withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("missing fixture files")
            return
        }
        let b64 = try String(contentsOf: b64URL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedJSON = try String(contentsOf: expectedJSONURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

        let gzBytes = try ShareCodec.base64urlDecode(b64)
        let decompressed = try Gzip.decompress(gzBytes)
        let decompressedString = String(data: decompressed, encoding: .utf8)
        XCTAssertEqual(decompressedString, expectedJSON)
    }
}
