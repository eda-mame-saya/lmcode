import AudioToolbox
import CoreMedia
import Foundation

/// Native high-quality recorder: 48 kHz / stereo / 24-bit PCM WAV.
/// Converts CMSampleBuffer on a dedicated queue and writes without Dart PCM streaming.
/// Experimental — smoothness-first (no intentional drops; tracks queue depth).
final class HqNativeRecorder {
  static let targetSampleRate: Double = 48_000
  static let channels = 2
  static let bitsPerSample = 24

  private let queue = DispatchQueue(label: "meeting.assist.hq.recorder")
  private var writer: HqWavFileWriter?
  private var startedAt: Date?
  private var framesWritten: UInt64 = 0
  private var chunksAccepted: UInt64 = 0
  private var pendingJobs = 0
  private var maxPendingJobs = 0
  private var convertFailures: UInt64 = 0
  private var writeFailures: UInt64 = 0
  private var lastError: String = ""

  private(set) var isRecording = false
  private(set) var isPaused = false
  private(set) var outputPath: String = ""

  func start(path: String) throws {
    try queue.sync {
      if writer != nil {
        throw AudioEngineError.screenCapture("高音質録音はすでに開始済みです")
      }
      let w = try HqWavFileWriter(
        path: path,
        sampleRate: Int(Self.targetSampleRate),
        channels: Self.channels,
        bitsPerSample: Self.bitsPerSample
      )
      writer = w
      outputPath = path
      startedAt = Date()
      framesWritten = 0
      chunksAccepted = 0
      pendingJobs = 0
      maxPendingJobs = 0
      convertFailures = 0
      writeFailures = 0
      lastError = ""
      isPaused = false
      isRecording = true
    }
  }

  /// Pause writing (capture may continue). Safe from any thread.
  func pause() {
    queue.sync {
      guard isRecording else { return }
      isPaused = true
    }
  }

  /// Resume writing after [pause].
  func resume() {
    queue.sync {
      guard isRecording else { return }
      isPaused = false
    }
  }

  /// Enqueue conversion + disk write. Does not block the capture callback for long.
  func append(sampleBuffer: CMSampleBuffer) {
    guard isRecording, !isPaused else { return }
    // Retain sample data by copying PCM floats on the capture thread lightly,
    // then do disk I/O on the write queue.
    guard let pcm = Self.convertToInterleaved24BitStereo48k(sampleBuffer) else {
      queue.async { [weak self] in
        self?.convertFailures &+= 1
      }
      return
    }
    guard !pcm.bytes.isEmpty else { return }

    queue.async { [weak self] in
      guard let self, let writer = self.writer, self.isRecording, !self.isPaused else { return }
      self.pendingJobs += 1
      if self.pendingJobs > self.maxPendingJobs {
        self.maxPendingJobs = self.pendingJobs
      }
      defer { self.pendingJobs = max(0, self.pendingJobs - 1) }

      do {
        try writer.append(pcm.bytes)
        self.framesWritten &+= UInt64(pcm.frames)
        self.chunksAccepted &+= 1
      } catch {
        self.writeFailures &+= 1
        self.lastError = error.localizedDescription
      }
    }
  }

  /// Finalize WAV and return stats. Safe to call from any thread.
  func stop() -> [String: Any] {
    queue.sync {
      isRecording = false
      isPaused = false
      let path = outputPath
      var dataBytes: UInt64 = 0
      if let writer {
        dataBytes = writer.dataBytes
        do {
          try writer.finalize()
        } catch {
          lastError = error.localizedDescription
        }
        self.writer = nil
      }
      let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
      let durationSec =
        Self.targetSampleRate > 0
          ? Double(framesWritten) / Self.targetSampleRate
          : 0
      let result: [String: Any] = [
        "path": path,
        "sampleRate": Int(Self.targetSampleRate),
        "channels": Self.channels,
        "bitsPerSample": Self.bitsPerSample,
        "framesWritten": Int(clamping: framesWritten),
        "dataBytes": Int(clamping: dataBytes),
        "chunksAccepted": Int(clamping: chunksAccepted),
        "maxPendingJobs": maxPendingJobs,
        "convertFailures": Int(clamping: convertFailures),
        "writeFailures": Int(clamping: writeFailures),
        "wallClockSec": elapsed,
        "audioDurationSec": durationSec,
        "lastError": lastError,
      ]
      startedAt = nil
      outputPath = ""
      return result
    }
  }

  /// Stop without finalizing a usable file; delete the output path if present.
  func discard() -> [String: Any] {
    let path: String = queue.sync {
      isRecording = false
      isPaused = false
      let p = outputPath
      if let writer {
        writer.abandon()
      }
      writer = nil
      startedAt = nil
      outputPath = ""
      return p
    }
    if !path.isEmpty {
      try? FileManager.default.removeItem(atPath: path)
    }
    return [
      "path": "",
      "discarded": true,
      "sampleRate": Int(Self.targetSampleRate),
      "channels": Self.channels,
      "bitsPerSample": Self.bitsPerSample,
      "framesWritten": 0,
      "dataBytes": 0,
      "chunksAccepted": 0,
      "maxPendingJobs": 0,
      "convertFailures": 0,
      "writeFailures": 0,
      "wallClockSec": 0.0,
      "audioDurationSec": 0.0,
      "lastError": "",
    ]
  }

  // MARK: - Convert

  private struct PcmChunk {
    let bytes: Data
    let frames: Int
  }

  /// Float / Int16 source → interleaved 24-bit LE stereo @ 48 kHz.
  private static func convertToInterleaved24BitStereo48k(
    _ sampleBuffer: CMSampleBuffer
  ) -> PcmChunk? {
    guard sampleBuffer.isValid else { return nil }
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
    else {
      return nil
    }
    let asbd = asbdPtr.pointee
    let sourceRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : targetSampleRate
    let sourceChannels = max(Int(asbd.mChannelsPerFrame), 1)

    var blockBuffer: CMBlockBuffer?
    var sizeNeeded = 0
    _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &sizeNeeded,
      bufferListOut: nil,
      bufferListSize: 0,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: nil
    )
    guard sizeNeeded > 0 else { return nil }

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: sizeNeeded,
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: list,
      bufferListSize: sizeNeeded,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return nil }

    // Deinterleave / normalize to stereo float arrays (L, R).
    // SCK stereo is often planar (2 buffers × 1ch), not interleaved.
    var left = [Float]()
    var right = [Float]()
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let frameHint = max(CMSampleBufferGetNumSamples(sampleBuffer), 0)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let isNonInterleaved =
      (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        || (buffers.count >= 2 && buffers.allSatisfy { $0.mNumberChannels <= 1 })

    if isNonInterleaved && buffers.count >= 1 {
      // Planar: buffer[0]=L, buffer[1]=R (mono duplicate if only one plane).
      let plane0 = Self.floatsFromPlanarBuffer(
        buffers[0],
        isFloat: isFloat,
        bitsPerChannel: Int(asbd.mBitsPerChannel)
      )
      let plane1: [Float]
      if buffers.count >= 2 {
        plane1 = Self.floatsFromPlanarBuffer(
          buffers[1],
          isFloat: isFloat,
          bitsPerChannel: Int(asbd.mBitsPerChannel)
        )
      } else {
        plane1 = plane0
      }
      let frames = min(
        plane0.count,
        plane1.isEmpty ? plane0.count : plane1.count,
        frameHint > 0 ? frameHint : Int.max
      )
      guard frames > 0 else { return nil }
      left = Array(plane0.prefix(frames))
      right = plane1.isEmpty
        ? left
        : Array(plane1.prefix(frames))
    } else {
      // Interleaved (or single buffer treated as interleaved).
      for buffer in buffers {
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
        let bufferChannels = max(
          Int(buffer.mNumberChannels),
          sourceChannels,
          1
        )

        if isFloat {
          let floats = data.assumingMemoryBound(to: Float.self)
          let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
          let frames = total / bufferChannels
          left.reserveCapacity(left.count + frames)
          right.reserveCapacity(right.count + frames)
          for f in 0..<frames {
            if bufferChannels >= 2 {
              left.append(floats[f * bufferChannels])
              right.append(floats[f * bufferChannels + 1])
            } else {
              let s = floats[f * bufferChannels]
              left.append(s)
              right.append(s)
            }
          }
        } else if asbd.mBitsPerChannel == 16 {
          let ints = data.assumingMemoryBound(to: Int16.self)
          let total = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
          let frames = total / bufferChannels
          left.reserveCapacity(left.count + frames)
          right.reserveCapacity(right.count + frames)
          for f in 0..<frames {
            if bufferChannels >= 2 {
              left.append(Float(ints[f * bufferChannels]) / Float(Int16.max))
              right.append(Float(ints[f * bufferChannels + 1]) / Float(Int16.max))
            } else {
              let s = Float(ints[f * bufferChannels]) / Float(Int16.max)
              left.append(s)
              right.append(s)
            }
          }
        }
      }
      if frameHint > 0, left.count > frameHint {
        left = Array(left.prefix(frameHint))
        right = Array(right.prefix(frameHint))
      }
    }

    guard !left.isEmpty else { return nil }
    if right.count != left.count {
      // Keep L/R aligned; pad missing side by duplication.
      if right.count < left.count {
        right.append(contentsOf: Array(left.suffix(left.count - right.count)))
      } else {
        left.append(contentsOf: Array(right.suffix(right.count - left.count)))
      }
    }

    let (outL, outR) = resampleStereo(
      left: left,
      right: right,
      sourceRate: sourceRate,
      targetRate: targetSampleRate
    )
    let frames = outL.count
    var bytes = Data()
    bytes.reserveCapacity(frames * channels * (bitsPerSample / 8))
    for i in 0..<frames {
      appendInt24LE(&bytes, floatSample: outL[i])
      appendInt24LE(&bytes, floatSample: outR[i])
    }
    return PcmChunk(bytes: bytes, frames: frames)
  }

  private static func floatsFromPlanarBuffer(
    _ buffer: AudioBuffer,
    isFloat: Bool,
    bitsPerChannel: Int
  ) -> [Float] {
    guard let data = buffer.mData, buffer.mDataByteSize > 0 else { return [] }
    if isFloat {
      let floats = data.assumingMemoryBound(to: Float.self)
      let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
      return Array(UnsafeBufferPointer(start: floats, count: count))
    }
    if bitsPerChannel == 16 {
      let ints = data.assumingMemoryBound(to: Int16.self)
      let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
      var out = [Float]()
      out.reserveCapacity(count)
      for i in 0..<count {
        out.append(Float(ints[i]) / Float(Int16.max))
      }
      return out
    }
    return []
  }

  private static func resampleStereo(
    left: [Float],
    right: [Float],
    sourceRate: Double,
    targetRate: Double
  ) -> ([Float], [Float]) {
    if abs(sourceRate - targetRate) < 0.5 {
      return (left, right)
    }
    let ratio = sourceRate / targetRate
    let outCount = max(Int(Double(left.count) / ratio), 1)
    var outL = [Float](repeating: 0, count: outCount)
    var outR = [Float](repeating: 0, count: outCount)
    for i in 0..<outCount {
      let srcIndex = Double(i) * ratio
      let leftIdx = Int(srcIndex)
      let rightIdx = min(leftIdx + 1, left.count - 1)
      let frac = Float(srcIndex - Double(leftIdx))
      outL[i] = left[leftIdx] * (1 - frac) + left[rightIdx] * frac
      outR[i] = right[leftIdx] * (1 - frac) + right[rightIdx] * frac
    }
    return (outL, outR)
  }

  private static func appendInt24LE(_ data: inout Data, floatSample: Float) {
    let clipped = max(-1.0, min(1.0, floatSample))
    // 24-bit signed full scale
    var v = Int32((clipped * 8_388_607.0).rounded())
    v = max(-8_388_608, min(8_388_607, v))
    data.append(UInt8(v & 0xFF))
    data.append(UInt8((v >> 8) & 0xFF))
    data.append(UInt8((v >> 16) & 0xFF))
  }
}
