import CoreAudio
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures system / meeting app speaker audio via ScreenCaptureKit (macOS 13+).
@available(macOS 13.0, *)
final class SystemAudioCaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput {
  /// Below this RMS, treat as silence (SCK keeps delivering zero-ish buffers).
  private static let activityThreshold: Float = 0.008

  private var stream: SCStream?
  private let sampleHandlerQueue = DispatchQueue(label: "meeting.assist.system.audio")

  private(set) var isRunning = false
  private(set) var isReceiving = false
  private(set) var lastLevel: Float = 0
  private(set) var framesReceived: UInt64 = 0

  private var silenceWorkItem: DispatchWorkItem?
  var onActivity: ((Bool, Float, UInt64) -> Void)?
  /// Raw capture buffers for AmiVoice PCM bridging (optional).
  var onSampleBuffer: ((CMSampleBuffer) -> Void)?

  func start() async throws {
    stop()

    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    guard let display = content.displays.first else {
      throw AudioEngineError.screenCapture(
        "画面（ディスプレイ）を取得できません。画面収録権限を確認してください。"
      )
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.sampleRate = 48_000
    // Stereo: HQ 録音用。STT 側（AmiVoicePcmBridge）は従来どおりモノ化する。
    config.channelCount = 2
    // Minimal video is required by SCK even for audio-focused capture.
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    config.showsCursor = false

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
    try await stream.startCapture()

    self.stream = stream
    isRunning = true
    isReceiving = false
    framesReceived = 0
    lastLevel = 0
  }

  func stop() {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    if let stream {
      stream.stopCapture { _ in }
    }
    stream = nil
    isRunning = false
    isReceiving = false
    lastLevel = 0
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    isRunning = false
    isReceiving = false
    onActivity?(false, 0, framesReceived)
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid else { return }

    let frames = UInt64(max(CMSampleBufferGetNumSamples(sampleBuffer), 0))
    guard frames > 0 else { return }
    framesReceived &+= frames
    onSampleBuffer?(sampleBuffer)

    let rms = Self.rmsLevel(of: sampleBuffer)
    lastLevel = rms

    // ScreenCaptureKit delivers continuous buffers even for silence.
    // Only surface "受け取り中" when there is real amplitude.
    if rms >= Self.activityThreshold {
      markReceiving(true)
    } else {
      onActivity?(isReceiving, rms, framesReceived)
    }
  }

  private func markReceiving(_ active: Bool) {
    silenceWorkItem?.cancel()
    if active {
      isReceiving = true
      onActivity?(true, lastLevel, framesReceived)
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.isReceiving = false
        self.lastLevel = 0
        self.onActivity?(false, 0, self.framesReceived)
      }
      silenceWorkItem = work
      sampleHandlerQueue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
  }

  private static func rmsLevel(of sampleBuffer: CMSampleBuffer) -> Float {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
      return 0
    }
    let asbd = asbdPtr.pointee

    var blockBuffer: CMBlockBuffer?
    var bufferListSizeNeeded = 0
    var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &bufferListSizeNeeded,
      bufferListOut: nil,
      bufferListSize: 0,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: nil
    )
    guard bufferListSizeNeeded > 0 else { return 0 }

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: bufferListSizeNeeded,
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    let audioBufferList = raw.assumingMemoryBound(to: AudioBufferList.self)

    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: audioBufferList,
      bufferListSize: bufferListSizeNeeded,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return 0 }

    let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
    var sumSquares: Float = 0
    var sampleCount = 0

    for buffer in buffers {
      guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
      let channels = max(Int(buffer.mNumberChannels), 1)

      if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
        let floats = data.assumingMemoryBound(to: Float.self)
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        for i in 0..<count {
          let s = floats[i]
          sumSquares += s * s
        }
        sampleCount += count
      } else if asbd.mBitsPerChannel == 16 {
        let ints = data.assumingMemoryBound(to: Int16.self)
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
        for i in 0..<count {
          let s = Float(ints[i]) / Float(Int16.max)
          sumSquares += s * s
        }
        sampleCount += count
      } else {
        _ = channels
      }
    }

    guard sampleCount > 0 else { return 0 }
    return sqrt(sumSquares / Float(sampleCount))
  }
}
