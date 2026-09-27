import Foundation
import CZlib

// MARK: - Gzip
//
// Share links are gzip-framed so they round-trip through the browser's
// `CompressionStream('gzip')` / `DecompressionStream('gzip')`. zlib's deflate/inflate
// with windowBits = 15 + 16 produces and consumes that exact gzip container (a gzip
// header + deflate stream + CRC32/size trailer), so either side can produce a share
// link the other reads.

public enum GzipError: Error, Equatable {
    /// zlib rejected the input or setup with this return code.
    case zlib(Int32)
    /// Decompression would exceed the caller's `maxOutput` guard.
    case outputTooLarge
    /// The stream ended without a proper gzip trailer (truncated/corrupt input).
    case truncated
}

public enum Gzip {

    /// gzip framing: raw deflate (-15) with the gzip wrapper added (+16).
    private static let gzipWindowBits: Int32 = 15 + 16
    private static let chunkSize = 64 * 1024

    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        let rc = CZlib_deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, gzipWindowBits, 8, Z_DEFAULT_STRATEGY)
        guard rc == Z_OK else { throw GzipError.zlib(rc) }
        defer { deflateEnd(&stream) }

        var input = [UInt8](data)
        var output = Data()
        var outBuffer = [UInt8](repeating: 0, count: chunkSize)

        try input.withUnsafeMutableBufferPointer { inPtr in
            stream.next_in = inPtr.baseAddress
            stream.avail_in = UInt32(inPtr.count)

            var result: Int32 = Z_OK
            repeat {
                try outBuffer.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = UInt32(outPtr.count)
                    result = deflate(&stream, Z_FINISH)
                    guard result == Z_OK || result == Z_STREAM_END else {
                        throw GzipError.zlib(result)
                    }
                    let produced = outPtr.count - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(outPtr.baseAddress!, count: produced)
                    }
                }
            } while result != Z_STREAM_END
        }
        return output
    }

    public static func decompress(_ data: Data, maxOutput: Int = 4_000_000) throws -> Data {
        var stream = z_stream()
        let rc = CZlib_inflateInit2(&stream, gzipWindowBits)
        guard rc == Z_OK else { throw GzipError.zlib(rc) }
        defer { inflateEnd(&stream) }

        var input = [UInt8](data)
        var output = Data()
        var outBuffer = [UInt8](repeating: 0, count: chunkSize)
        var finished = false

        try input.withUnsafeMutableBufferPointer { inPtr in
            stream.next_in = inPtr.baseAddress
            stream.avail_in = UInt32(inPtr.count)

            var result: Int32 = Z_OK
            while result != Z_STREAM_END {
                try outBuffer.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = UInt32(outPtr.count)
                    result = inflate(&stream, Z_NO_FLUSH)
                    guard result == Z_OK || result == Z_STREAM_END || result == Z_BUF_ERROR else {
                        throw GzipError.zlib(result)
                    }
                    let produced = outPtr.count - Int(stream.avail_out)
                    if produced > 0 {
                        if output.count + produced > maxOutput { throw GzipError.outputTooLarge }
                        output.append(outPtr.baseAddress!, count: produced)
                    }
                }
                if result == Z_BUF_ERROR {
                    // No further progress possible: the stream ran out of input before
                    // reaching its trailer — truncated or corrupt data.
                    break
                }
            }
            finished = (result == Z_STREAM_END)
        }
        guard finished else { throw GzipError.truncated }
        return output
    }
}
