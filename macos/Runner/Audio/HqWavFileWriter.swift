import Foundation

/// Streaming WAV writer (PCM). Header sizes are patched on finalize.
/// Experimental: used by high-quality recording (48 kHz / stereo / 24-bit).
final class HqWavFileWriter {
  private let fileHandle: FileHandle
  private let sampleRate: Int
  private let channels: Int
  private let bitsPerSample: Int
  private(set) var dataBytes: UInt64 = 0
  private let path: String

  var filePath: String { path }

  init(
    path: String,
    sampleRate: Int,
    channels: Int,
    bitsPerSample: Int
  ) throws {
    precondition(bitsPerSample % 8 == 0)
    self.path = path
    self.sampleRate = sampleRate
    self.channels = channels
    self.bitsPerSample = bitsPerSample

    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: parent,
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(atPath: path)
    }
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let handle = FileHandle(forWritingAtPath: path) else {
      throw AudioEngineError.screenCapture("WAV ファイルを開けません: \(path)")
    }
    fileHandle = handle
    try writeHeader(dataSize: 0)
  }

  /// Append raw interleaved PCM bytes (little-endian).
  func append(_ data: Data) throws {
    guard !data.isEmpty else { return }
    try fileHandle.write(contentsOf: data)
    dataBytes &+= UInt64(data.count)
  }

  /// Patch RIFF / data chunk sizes and close.
  func finalize() throws {
    try fileHandle.synchronize()
    try fileHandle.seek(toOffset: 0)
    try writeHeader(dataSize: dataBytes)
    try fileHandle.synchronize()
    try fileHandle.close()
  }

  /// Close without patching header (for discard).
  func abandon() {
    try? fileHandle.close()
  }

  private func writeHeader(dataSize: UInt64) throws {
    let blockAlign = channels * (bitsPerSample / 8)
    let byteRate = sampleRate * blockAlign
    let dataSize32 = UInt32(clamping: dataSize)
    let riffSize = UInt32(clamping: 36 + dataSize)

    var header = Data()
    header.reserveCapacity(44)
    header.append(contentsOf: Array("RIFF".utf8))
    header.appendUint32LE(riffSize)
    header.append(contentsOf: Array("WAVE".utf8))
    header.append(contentsOf: Array("fmt ".utf8))
    header.appendUint32LE(16) // PCM fmt chunk size
    header.appendUint16LE(1) // WAVE_FORMAT_PCM
    header.appendUint16LE(UInt16(channels))
    header.appendUint32LE(UInt32(sampleRate))
    header.appendUint32LE(UInt32(byteRate))
    header.appendUint16LE(UInt16(blockAlign))
    header.appendUint16LE(UInt16(bitsPerSample))
    header.append(contentsOf: Array("data".utf8))
    header.appendUint32LE(dataSize32)
    try fileHandle.write(contentsOf: header)
  }
}

private extension Data {
  mutating func appendUint16LE(_ value: UInt16) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }

  mutating func appendUint32LE(_ value: UInt32) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }
}
