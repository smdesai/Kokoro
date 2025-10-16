import Foundation

/// Streams float PCM samples to a 16-bit mono WAV file without buffering the entire audio in memory.
/// Writes a placeholder header on init and patches sizes on `finish()`.
final class WavStreamWriter {
    private let fileHandle: FileHandle
    private let sampleRate: Double
    private var totalSamples: UInt64 = 0
    private var isClosed = false

    private static let pcmStride = MemoryLayout<Int16>.stride

    init(outputURL: URL, sampleRate: Double) throws {
        self.sampleRate = sampleRate

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let parentDirectory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDirectory, withIntermediateDirectories: true)

        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: outputURL.path])
        }

        self.fileHandle = try FileHandle(forWritingTo: outputURL)
        try writePlaceholderHeader()
    }

    deinit {
        try? finish()
    }

    private func writePlaceholderHeader() throws {
        var header = Data()
        header.reserveCapacity(44)

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: UInt32(0).littleEndianBytes)
        header.append(contentsOf: "WAVE".utf8)

        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: UInt32(16).littleEndianBytes)
        header.append(contentsOf: UInt16(1).littleEndianBytes)
        header.append(contentsOf: UInt16(1).littleEndianBytes)
        header.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        let byteRate = UInt32(sampleRate * Double(Self.pcmStride))
        header.append(contentsOf: byteRate.littleEndianBytes)
        header.append(contentsOf: UInt16(Self.pcmStride).littleEndianBytes)
        header.append(contentsOf: UInt16(16).littleEndianBytes)

        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: UInt32(0).littleEndianBytes)

        try fileHandle.write(contentsOf: header)
    }

    /// Append PCM samples by clipping each value to [-1, 1] before quantising to Int16.
    func append(samples: UnsafeBufferPointer<Float>) throws {
        guard let baseAddress = samples.baseAddress, samples.count > 0 else { return }

        var buffer = Data()
        buffer.reserveCapacity(samples.count * Self.pcmStride)
        for index in 0 ..< samples.count {
            let clipped = max(-1.0, min(1.0, Double(baseAddress[index])))
            var quantised = Int16(clipped * 32767.0).littleEndian
            withUnsafeBytes(of: &quantised) { buffer.append(contentsOf: $0) }
        }

        try fileHandle.write(contentsOf: buffer)
        totalSamples += UInt64(samples.count)
    }

    /// Append PCM samples provided via any sequence of Float values.
    func append<S>(samples: S) throws where S: Sequence, S.Element == Float {
        var buffer = Data()
        var sampleCount: UInt64 = 0
        for value in samples {
            let clipped = max(-1.0, min(1.0, Double(value)))
            var quantised = Int16(clipped * 32767.0).littleEndian
            withUnsafeBytes(of: &quantised) { buffer.append(contentsOf: $0) }
            sampleCount += 1
        }
        guard sampleCount > 0 else { return }
        try fileHandle.write(contentsOf: buffer)
        totalSamples += sampleCount
    }

    /// Append `sampleCount` zero-valued samples.
    func appendSilence(sampleCount: Int) throws {
        guard sampleCount > 0 else { return }
        let zeroData = Data(count: sampleCount * Self.pcmStride)
        try fileHandle.write(contentsOf: zeroData)
        totalSamples += UInt64(sampleCount)
    }

    /// Finalise the WAV header and close the file handle.
    func finish() throws {
        guard !isClosed else { return }
        isClosed = true

        let dataSize = totalSamples * UInt64(Self.pcmStride)
        let riffSize = UInt32(clamping: dataSize + 36)
        let dataChunkSize = UInt32(clamping: dataSize)

        try fileHandle.seek(toOffset: 4)
        try fileHandle.write(contentsOf: riffSize.littleEndianBytes)
        try fileHandle.seek(toOffset: 40)
        try fileHandle.write(contentsOf: dataChunkSize.littleEndianBytes)
        try fileHandle.close()
    }
}

extension UInt16 {
    fileprivate var littleEndianBytes: [UInt8] {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}

extension UInt32 {
    fileprivate var littleEndianBytes: [UInt8] {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
