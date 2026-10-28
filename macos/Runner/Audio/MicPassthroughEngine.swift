import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation

/// Meters mic input via AVCapture (reliable callbacks on macOS) and routes the
/// same captured PCM to a virtual output (BlackHole) via AVAudioPlayerNode.
///
/// Important: do NOT open the physical mic twice (AVCapture + AVAudioEngine input).
/// Dual-open often yields silent BlackHole output on macOS.
final class MicPassthroughEngine: NSObject {
  private let captureSession = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "meeting.assist.mic.capture")
  private let passthroughQueue = DispatchQueue(label: "meeting.assist.mic.passthrough")
  private var passthroughEngine: AVAudioEngine?
  private var passthroughPlayer: AVAudioPlayerNode?
  private var passthroughFormat: AVAudioFormat?
  private var passthroughConverter: AVAudioConverter?

  private(set) var isRunning = false
  private(set) var isHearing = false
  private(set) var inputDeviceName: String = ""
  private(set) var virtualOutputName: String = ""
  private(set) var lastLevel: Float = 0
  private(set) var lastPeak: Float = 0
  private(set) var framesPassed: UInt64 = 0
  private(set) var callbackCount: UInt64 = 0
  private(set) var passthroughEnabled = false
  private(set) var lastSetupWarning: String = ""
  private(set) var inputFormatDescription: String = ""
  /// When true, mic is not forwarded to BlackHole / STT mix (levels still update).
  private(set) var isMuted = false

  private var silenceWorkItem: DispatchWorkItem?
  private var scheduledPassthroughBuffers = 0

  var onActivity: ((Float, UInt64) -> Void)?
  /// Raw capture buffers for AmiVoice PCM bridging (optional).
  var onSampleBuffer: ((CMSampleBuffer) -> Void)?

  private static let activityThreshold: Float = 0.003
  private static let maxQueuedPassthroughBuffers = 12

  var captureDiagnosis: String {
    if !isRunning { return "停止中" }
    if callbackCount == 0 {
      return "コールバック未受信（入力がエンジンに流れていない）"
    }
    if framesPassed == 0 {
      return "コールバックはあるがフレーム数0"
    }
    if lastPeak < Self.activityThreshold {
      return "バッファ受信中（無音に近い / peak=\(String(format: "%.4f", lastPeak))）"
    }
    return "入力あり（peak=\(String(format: "%.4f", lastPeak))）"
  }

  func start(inputUID: String?, virtualOutputUID: String?) throws {
    stop()
    lastSetupWarning = ""
    scheduledPassthroughBuffers = 0

    let devices = AudioDeviceEnumerator.listDevices()
    let input: AudioDeviceInfo
    if let inputUID,
       let match = devices.first(where: {
         $0.uid == inputUID && $0.isInput && !$0.isVirtualCandidate
       }) {
      input = match
    } else if let preferred = AudioDeviceEnumerator.preferredPhysicalInput(
      excludingVirtualUID: nil
    ) {
      input = preferred
    } else {
      throw AudioEngineError.inputDeviceMissing
    }

    let virtual: AudioDeviceInfo?
    if let virtualOutputUID,
       let match = devices.first(where: { $0.uid == virtualOutputUID && $0.isOutput }) {
      virtual = match
    } else {
      virtual = AudioDeviceEnumerator.preferredVirtualOutput()
    }

    inputDeviceName = input.name
    virtualOutputName = virtual?.name ?? ""

    try startCaptureMonitor(preferredName: input.name, preferredUID: input.uid)

    if let virtual {
      do {
        try startPassthroughOutput(virtualOutputID: virtual.id)
        passthroughEnabled = true
        NSLog(
          "[OnlineAudio] passthrough ready: %@ → %@",
          inputDeviceName,
          virtualOutputName
        )
      } catch {
        passthroughEnabled = false
        lastSetupWarning =
          "マイク入力の監視は開始済み。仮想マイクへのパススルーのみ失敗: \(error.localizedDescription)"
        NSLog("[OnlineAudio] passthrough failed: %@", error.localizedDescription)
      }
    } else {
      passthroughEnabled = false
      lastSetupWarning = "仮想マイク未検出のため、マイクはレベル監視のみです。"
    }

    isRunning = true
  }

  func stop() {
    silenceWorkItem?.cancel()
    silenceWorkItem = nil

    if captureSession.isRunning {
      captureSession.stopRunning()
    }
    for output in captureSession.outputs {
      captureSession.removeOutput(output)
    }
    for input in captureSession.inputs {
      captureSession.removeInput(input)
    }

    passthroughQueue.sync {
      if let player = passthroughPlayer {
        player.stop()
      }
      if let engine = passthroughEngine {
        if engine.isRunning {
          engine.stop()
        }
        engine.reset()
      }
      passthroughPlayer = nil
      passthroughEngine = nil
      passthroughFormat = nil
      passthroughConverter = nil
      scheduledPassthroughBuffers = 0
    }

    isRunning = false
    isHearing = false
    lastLevel = 0
    lastPeak = 0
    passthroughEnabled = false
    isMuted = false
  }

  /// Mutes mic passthrough to BlackHole and STT mix. Capture/levels stay active.
  func setMuted(_ muted: Bool) {
    isMuted = muted
  }

  // MARK: - AVCapture monitor (source of truth for levels / PCM / passthrough)

  private func startCaptureMonitor(preferredName: String, preferredUID: String) throws {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .high

    let discoveryDevices: [AVCaptureDevice]
    if #available(macOS 14.0, *) {
      discoveryDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
      ).devices
    } else {
      discoveryDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInMicrophone, .externalUnknown],
        mediaType: .audio,
        position: .unspecified
      ).devices
    }

    let captureDevice =
      discoveryDevices.first(where: { $0.localizedName == preferredName })
      ?? discoveryDevices.first(where: { $0.uniqueID == preferredUID })
      ?? AVCaptureDevice.default(for: .audio)

    guard let captureDevice else {
      captureSession.commitConfiguration()
      throw AudioEngineError.inputDeviceMissing
    }

    inputDeviceName = captureDevice.localizedName

    let input = try AVCaptureDeviceInput(device: captureDevice)
    guard captureSession.canAddInput(input) else {
      captureSession.commitConfiguration()
      throw AudioEngineError.coreAudio(-1, "AVCapture にマイク入力を追加できません。")
    }
    captureSession.addInput(input)

    let output = AVCaptureAudioDataOutput()
    // Deliver PCM that we can meter and forward to BlackHole.
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: 48_000,
    ]
    output.setSampleBufferDelegate(self, queue: captureQueue)

    guard captureSession.canAddOutput(output) else {
      captureSession.commitConfiguration()
      throw AudioEngineError.coreAudio(-1, "AVCapture に音声出力を追加できません。")
    }
    captureSession.addOutput(output)
    captureSession.commitConfiguration()

    inputFormatDescription = "AVCapture / \(captureDevice.localizedName)"
    framesPassed = 0
    callbackCount = 0
    lastLevel = 0
    lastPeak = 0
    isHearing = false

    captureSession.startRunning()
    guard captureSession.isRunning else {
      throw AudioEngineError.coreAudio(-1, "AVCaptureSession を開始できません。マイク権限を確認してください。")
    }
    NSLog("[OnlineAudio] AVCapture monitor started: %@", captureDevice.localizedName)
  }

  // MARK: - BlackHole output (player feeds captured PCM)

  private func startPassthroughOutput(virtualOutputID: AudioDeviceID) throws {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)

    try Self.setCurrentDevice(engine.outputNode.audioUnit, deviceID: virtualOutputID)

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
      )
    else {
      throw AudioEngineError.coreAudio(-1, "パススルー用フォーマットを作成できません。")
    }

    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1.0
    engine.prepare()
    try engine.start()
    player.play()

    passthroughEngine = engine
    passthroughPlayer = player
    passthroughFormat = format
  }

  private func enqueuePassthrough(sampleBuffer: CMSampleBuffer) {
    guard passthroughEnabled,
          let player = passthroughPlayer,
          let outFormat = passthroughFormat
    else { return }

    passthroughQueue.async { [weak self] in
      guard let self else { return }
      // Prevent unbounded queue if downstream is stalled.
      if self.scheduledPassthroughBuffers >= Self.maxQueuedPassthroughBuffers {
        return
      }
      guard
        let pcmBuffer = self.makePlayableBuffer(from: sampleBuffer, outFormat: outFormat)
      else { return }

      self.scheduledPassthroughBuffers += 1
      player.scheduleBuffer(pcmBuffer) { [weak self] in
        self?.passthroughQueue.async {
          self?.scheduledPassthroughBuffers = max(0, (self?.scheduledPassthroughBuffers ?? 1) - 1)
        }
      }
    }
  }

  private func makePlayableBuffer(
    from sampleBuffer: CMSampleBuffer,
    outFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let asbd = CMSampleBufferGetFormatDescription(sampleBuffer)
      .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
    let sampleRate = (asbd?.mSampleRate ?? 0) > 0 ? asbd!.mSampleRate : 48_000
    guard
      let monoFloat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else { return nil }

    guard let source = Self.copyMonoFloat(from: sampleBuffer, format: monoFloat) else {
      return nil
    }

    if abs(monoFloat.sampleRate - outFormat.sampleRate) < 0.5,
       monoFloat.channelCount == outFormat.channelCount,
       monoFloat.commonFormat == outFormat.commonFormat,
       !outFormat.isInterleaved {
      return source
    }

    if passthroughConverter == nil
      || passthroughConverter?.inputFormat != monoFloat
      || passthroughConverter?.outputFormat != outFormat {
      passthroughConverter = AVAudioConverter(from: monoFloat, to: outFormat)
    }
    guard let converter = passthroughConverter else { return nil }

    let ratio = outFormat.sampleRate / monoFloat.sampleRate
    let outFrames = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio) + 16)
    guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else {
      return nil
    }

    var error: NSError?
    var consumed = false
    let status = converter.convert(to: out, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return source
    }
    guard status != .error, error == nil, out.frameLength > 0 else { return nil }
    return out
  }

  private func handleMeter(rms: Float, peak: Float, frames: UInt64) {
    callbackCount &+= 1
    framesPassed &+= frames
    lastLevel = rms
    lastPeak = peak

    if peak >= Self.activityThreshold {
      markHearing(true)
    } else {
      onActivity?(rms, framesPassed)
    }
  }

  private func markHearing(_ active: Bool) {
    silenceWorkItem?.cancel()
    if active {
      isHearing = true
      onActivity?(lastLevel, framesPassed)
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.isHearing = false
        self.onActivity?(self.lastLevel, self.framesPassed)
      }
      silenceWorkItem = work
      captureQueue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
  }

  private static func setCurrentDevice(_ unit: AudioUnit?, deviceID: AudioDeviceID) throws {
    guard let unit else {
      throw AudioEngineError.halComponentMissing
    }
    var id = deviceID
    let status = AudioUnitSetProperty(
      unit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &id,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
      throw AudioEngineError.coreAudio(status, "CurrentDevice")
    }
  }

  private static func copyMonoFloat(
    from sampleBuffer: CMSampleBuffer,
    format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let frameCount = AVAudioFrameCount(max(CMSampleBufferGetNumSamples(sampleBuffer), 0))
    guard frameCount > 0 else { return nil }
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
          let dst = out.floatChannelData?[0]
    else { return nil }
    out.frameLength = frameCount

    var blockBuffer: CMBlockBuffer?
    var sizeNeeded = 0
    var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
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

    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
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

    let buffers = UnsafeMutableAudioBufferListPointer(list)
    guard let first = buffers.first, let src = first.mData, first.mDataByteSize > 0 else {
      return nil
    }

    let asbd = CMSampleBufferGetFormatDescription(sampleBuffer)
      .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
    let isFloat = (asbd?.mFormatFlags ?? 0) & kAudioFormatFlagIsFloat != 0
    let srcChannels = max(Int(asbd?.mChannelsPerFrame ?? 1), 1)

    if isFloat {
      let floats = src.assumingMemoryBound(to: Float.self)
      let n = min(
        Int(frameCount),
        Int(first.mDataByteSize) / (MemoryLayout<Float>.size * srcChannels)
      )
      for i in 0..<n {
        dst[i] = floats[i * srcChannels]
      }
      for i in n..<Int(frameCount) { dst[i] = 0 }
    } else {
      let ints = src.assumingMemoryBound(to: Int16.self)
      let n = min(
        Int(frameCount),
        Int(first.mDataByteSize) / (MemoryLayout<Int16>.size * srcChannels)
      )
      for i in 0..<n {
        dst[i] = Float(ints[i * srcChannels]) / Float(Int16.max)
      }
      for i in n..<Int(frameCount) { dst[i] = 0 }
    }
    return out
  }
}

extension MicPassthroughEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard sampleBuffer.isValid else { return }
    let frames = UInt64(max(CMSampleBufferGetNumSamples(sampleBuffer), 0))
    guard frames > 0 else { return }

    let metrics = Self.levelMetrics(from: sampleBuffer)
    if !isMuted {
      onSampleBuffer?(sampleBuffer)
      enqueuePassthrough(sampleBuffer: sampleBuffer)
    }
    handleMeter(rms: metrics.rms, peak: metrics.peak, frames: frames)
  }

  private struct LevelMetrics {
    let rms: Float
    let peak: Float
  }

  private static func levelMetrics(from sampleBuffer: CMSampleBuffer) -> LevelMetrics {
    var blockBuffer: CMBlockBuffer?
    var sizeNeeded = 0
    var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &sizeNeeded,
      bufferListOut: nil,
      bufferListSize: 0,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: nil
    )
    guard sizeNeeded > 0 else { return LevelMetrics(rms: 0, peak: 0) }

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: sizeNeeded,
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)

    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: list,
      bufferListSize: sizeNeeded,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return LevelMetrics(rms: 0, peak: 0) }

    let format = CMSampleBufferGetFormatDescription(sampleBuffer)
    let asbd = format.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

    var sum: Float = 0
    var peak: Float = 0
    var count = 0
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    for buffer in buffers {
      guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
      if let asbd, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
        let floats = data.assumingMemoryBound(to: Float.self)
        let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        for i in 0..<n {
          let s = floats[i]
          peak = max(peak, abs(s))
          sum += s * s
          count += 1
        }
      } else {
        let ints = data.assumingMemoryBound(to: Int16.self)
        let n = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
        for i in 0..<n {
          let s = Float(ints[i]) / Float(Int16.max)
          peak = max(peak, abs(s))
          sum += s * s
          count += 1
        }
      }
    }
    guard count > 0 else { return LevelMetrics(rms: 0, peak: 0) }
    return LevelMetrics(rms: sqrt(sum / Float(count)), peak: peak)
  }
}

enum AudioEngineError: LocalizedError {
  case virtualDeviceMissing
  case inputDeviceMissing
  case halComponentMissing
  case coreAudio(OSStatus, String)
  case screenCaptureUnavailable
  case screenCapture(String)

  var errorDescription: String? {
    switch self {
    case .virtualDeviceMissing:
      return "仮想マイク（LMCode / BlackHole 等）が見つかりません。インストール後に再試行してください。"
    case .inputDeviceMissing:
      return "物理マイクが見つかりません。"
    case .halComponentMissing:
      return "CoreAudio HAL コンポーネントを初期化できません。"
    case .coreAudio(let status, let where_):
      return "CoreAudio エラー (\(where_)): \(status)"
    case .screenCaptureUnavailable:
      return "この macOS では ScreenCaptureKit による音声取得に対応していません（macOS 13+）。"
    case .screenCapture(let message):
      return message
    }
  }
}
