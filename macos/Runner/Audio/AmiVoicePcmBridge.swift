import AudioToolbox
import CoreMedia
import Foundation

/// Collects mic/speaker audio, resamples to 16 kHz mono PCM16, mixes, and emits
/// chunks for AmiVoice (`LSB16K`).
final class AmiVoicePcmBridge {
  static let targetSampleRate: Double = 16_000

  private let lock = NSLock()
  private var micRing = [Int16]()
  private var speakerRing = [Int16]()
  private let maxRingSamples = 16_000 * 3 // ~3 seconds

  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "meeting.assist.pcm.bridge")

  var onPcmChunk: ((Data) -> Void)?
  private(set) var isRunning = false
  private(set) var chunksEmitted: UInt64 = 0

  func start() {
    stop()
    isRunning = true
    chunksEmitted = 0
    lock.lock()
    micRing.removeAll(keepingCapacity: true)
    speakerRing.removeAll(keepingCapacity: true)
    lock.unlock()

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
    timer.setEventHandler { [weak self] in
      self?.flushMixedChunk()
    }
    timer.resume()
    self.timer = timer
  }

  func stop() {
    timer?.cancel()
    timer = nil
    isRunning = false
    lock.lock()
    micRing.removeAll(keepingCapacity: false)
    speakerRing.removeAll(keepingCapacity: false)
    lock.unlock()
  }

  func pushMicSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard isRunning else { return }
    let samples = Self.pcm16Mono16k(from: sampleBuffer)
    guard !samples.isEmpty else { return }
    appendMic(samples)
  }

  func pushSpeakerSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard isRunning else { return }
    let samples = Self.pcm16Mono16k(from: sampleBuffer)
    guard !samples.isEmpty else { return }
    appendSpeaker(samples)
  }

  private func appendMic(_ samples: [Int16]) {
    lock.lock()
    micRing.append(contentsOf: samples)
    if micRing.count > maxRingSamples {
      micRing.removeFirst(micRing.count - maxRingSamples)
    }
    lock.unlock()
  }

  private func appendSpeaker(_ samples: [Int16]) {
    lock.lock()
    speakerRing.append(contentsOf: samples)
    if speakerRing.count > maxRingSamples {
      speakerRing.removeFirst(speakerRing.count - maxRingSamples)
    }
    lock.unlock()
  }

  private func flushMixedChunk() {
    lock.lock()
    let micCount = micRing.count
    let spkCount = speakerRing.count
    let n = min(max(micCount, spkCount), 3_200) // ~200ms @16k
    guard n > 0 else {
      lock.unlock()
      return
    }

    var mixed = [Int16](repeating: 0, count: n)
    for i in 0..<n {
      let m: Int32 = i < micCount ? Int32(micRing[i]) : 0
      let s: Int32 = i < spkCount ? Int32(speakerRing[i]) : 0
      let sum = m + s
      mixed[i] = Int16(clamping: max(Int32(Int16.min), min(Int32(Int16.max), sum)))
    }

    if micCount > 0 {
      micRing.removeFirst(min(n, micCount))
    }
    if spkCount > 0 {
      speakerRing.removeFirst(min(n, spkCount))
    }
    lock.unlock()

    let data = mixed.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
    chunksEmitted &+= 1
    onPcmChunk?(data)
  }

  // MARK: - Convert / resample

  static func pcm16Mono16k(from sampleBuffer: CMSampleBuffer) -> [Int16] {
    guard sampleBuffer.isValid else { return [] }
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
      return []
    }
    let asbd = asbdPtr.pointee
    let sourceRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : targetSampleRate

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
    guard sizeNeeded > 0 else { return [] }

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
    guard status == noErr else { return [] }

    var monoFloat = [Float]()
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let channels = max(Int(asbd.mChannelsPerFrame), 1)
    let frameHint = max(CMSampleBufferGetNumSamples(sampleBuffer), 0)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let isNonInterleaved =
      (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        || (buffers.count >= 2 && buffers.allSatisfy { $0.mNumberChannels <= 1 })

    if isNonInterleaved && buffers.count >= 1 {
      // Planar stereo: mix L/R planes per frame (do NOT concatenate planes in time).
      var planes = [[Float]]()
      planes.reserveCapacity(buffers.count)
      for buffer in buffers {
        planes.append(
          Self.floatsFromPlanarBuffer(
            buffer,
            isFloat: isFloat,
            bitsPerChannel: Int(asbd.mBitsPerChannel)
          )
        )
      }
      let frames = min(
        planes.map(\.count).min() ?? 0,
        frameHint > 0 ? frameHint : Int.max
      )
      guard frames > 0 else { return [] }
      monoFloat.reserveCapacity(frames)
      let planeCount = max(planes.count, 1)
      for f in 0..<frames {
        var sum: Float = 0
        for plane in planes {
          sum += plane[f]
        }
        monoFloat.append(sum / Float(planeCount))
      }
    } else {
      for buffer in buffers {
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
        if isFloat {
          let floats = data.assumingMemoryBound(to: Float.self)
          let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
          let frames = total / channels
          monoFloat.reserveCapacity(monoFloat.count + frames)
          for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
              sum += floats[f * channels + c]
            }
            monoFloat.append(sum / Float(channels))
          }
        } else {
          let ints = data.assumingMemoryBound(to: Int16.self)
          let total = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
          let frames = total / channels
          monoFloat.reserveCapacity(monoFloat.count + frames)
          for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
              sum += Float(ints[f * channels + c]) / Float(Int16.max)
            }
            monoFloat.append(sum / Float(channels))
          }
        }
      }
      if frameHint > 0, monoFloat.count > frameHint {
        monoFloat = Array(monoFloat.prefix(frameHint))
      }
    }

    return resampleTo16k(monoFloat, sourceRate: sourceRate)
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

  private static func resampleTo16k(_ input: [Float], sourceRate: Double) -> [Int16] {
    guard !input.isEmpty else { return [] }
    if abs(sourceRate - targetSampleRate) < 1 {
      return input.map { sample in
        let clipped = max(-1.0, min(1.0, sample))
        return Int16(clipped * Float(Int16.max))
      }
    }

    let ratio = sourceRate / targetSampleRate
    let outCount = max(Int(Double(input.count) / ratio), 1)
    var output = [Int16](repeating: 0, count: outCount)
    for i in 0..<outCount {
      let srcIndex = Double(i) * ratio
      let left = Int(srcIndex)
      let right = min(left + 1, input.count - 1)
      let frac = Float(srcIndex - Double(left))
      let sample = input[left] * (1 - frac) + input[right] * frac
      let clipped = max(-1.0, min(1.0, sample))
      output[i] = Int16(clipped * Float(Int16.max))
    }
    return output
  }
}
