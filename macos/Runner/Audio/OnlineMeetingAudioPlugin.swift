import AVFoundation
import Cocoa
import FlutterMacOS

/// Method / Event channel bridge for online-meeting audio capture (macOS).
final class OnlineMeetingAudioPlugin: NSObject {
  static let methodChannelName = "lmcode/online_audio"
  static let eventChannelName = "lmcode/online_audio_events"
  static let pcmEventChannelName = "lmcode/online_audio_pcm"

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let pcmEventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var pcmEventSink: FlutterEventSink?

  private let micEngine = MicPassthroughEngine()
  private let pcmBridge = AmiVoicePcmBridge()
  private let hqRecorder = HqNativeRecorder()
  private var systemEngine: AnyObject?
  private let stateLock = NSLock()
  private var statusTimer: Timer?

  private var selectedInputUID: String?
  private var selectedVirtualUID: String?
  private var lastErrorMessage: String = ""
  private var isStarting = false
  private var pcmStreamingEnabled = false
  /// HQ 実験セッション（STT なし・スピーカーのみ）。通常オンライン会議とは排他。
  private var hqExperimentActive = false

  /// 通常サイズに戻すためのフレーム（ミニ画面切替用）。
  private var savedWindowFrame: NSRect?
  private var savedWindowLevel: NSWindow.Level?
  /// すでにミニサイズへ縮めたあと（手前表示の切替では位置を動かさない）。
  private var compactWindowActive = false

  private var lastEmitAt: TimeInterval = 0

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: messenger
    )
    pcmEventChannel = FlutterEventChannel(
      name: Self.pcmEventChannelName,
      binaryMessenger: messenger
    )
    super.init()
    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)
    pcmEventChannel.setStreamHandler(PcmStreamHandler(plugin: self))

    micEngine.onActivity = { [weak self] _, _ in
      self?.emitThrottled()
    }
    micEngine.onSampleBuffer = { [weak self] sampleBuffer in
      guard let self, !self.hqExperimentActive else { return }
      self.pcmBridge.pushMicSampleBuffer(sampleBuffer)
    }
    pcmBridge.onPcmChunk = { [weak self] data in
      guard let self, self.pcmStreamingEnabled, !self.hqExperimentActive else { return }
      DispatchQueue.main.async {
        self.pcmEventSink?(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      result(currentStatus())
    case "listDevices":
      result(AudioDeviceEnumerator.listDevices().map(\.asDictionary))
    case "requestMicrophonePermission":
      requestMicrophonePermission(result: result)
    case "start":
      let args = call.arguments as? [String: Any]
      selectedInputUID = args?["inputUid"] as? String
      selectedVirtualUID = args?["virtualOutputUid"] as? String
      start(result: result)
    case "stop":
      stopAll()
      result(currentStatus())
    case "setPcmStreamingEnabled":
      let enabled = (call.arguments as? Bool) ?? false
      setPcmStreamingEnabled(enabled)
      result(nil)
    case "setMicMuted":
      let muted = (call.arguments as? Bool) ?? false
      micEngine.setMuted(muted)
      emit(currentStatus())
      result(currentStatus())
    case "selectDevices":
      let args = call.arguments as? [String: Any]
      selectedInputUID = args?["inputUid"] as? String
      selectedVirtualUID = args?["virtualOutputUid"] as? String
      result(currentStatus())
    case "startHqExperiment":
      startHqExperiment(arguments: call.arguments, result: result)
    case "stopHqExperiment":
      stopHqExperiment(result: result)
    case "pauseHqExperiment":
      pauseHqExperiment(result: result)
    case "resumeHqExperiment":
      resumeHqExperiment(result: result)
    case "discardHqExperiment":
      discardHqExperiment(result: result)
    case "setRecordingWindowMode":
      setRecordingWindowMode(arguments: call.arguments, result: result)
    case "revealInFinder":
      let path = (call.arguments as? String)
        ?? ((call.arguments as? [String: Any])?["path"] as? String)
      revealInFinder(path: path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setPcmStreamingEnabled(_ enabled: Bool) {
    pcmStreamingEnabled = enabled
    if enabled {
      if !pcmBridge.isRunning {
        pcmBridge.start()
      }
    } else {
      // Keep collecting only while session is active; stop bridge when capture stops.
    }
  }

  private func startHqExperiment(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    if hqExperimentActive || hqRecorder.isRecording {
      result(
        FlutterError(
          code: "hq_already_running",
          message: "高音質録音実験はすでに実行中です。",
          details: nil
        )
      )
      return
    }
    if isStarting || micEngine.isRunning || systemEngine != nil {
      result(
        FlutterError(
          code: "session_busy",
          message: "通常のオンライン会議キャプチャが動作中です。停止してから実験してください。",
          details: nil
        )
      )
      return
    }

    let args = arguments as? [String: Any]
    guard let path = args?["path"] as? String, !path.isEmpty else {
      result(
        FlutterError(
          code: "invalid_path",
          message: "保存先 path が必要です。",
          details: nil
        )
      )
      return
    }

    isStarting = true
    Task { [self] in
      do {
        // HQ 実験はスピーカー（会議ツール再生音）のみ。STT / マイク横取りは起動しない。
        try self.hqRecorder.start(path: path)
        self.hqExperimentActive = true

        if #available(macOS 13.0, *) {
          let engine = SystemAudioCaptureEngine()
          engine.onActivity = { _, _, _ in
            self.emitThrottled()
          }
          engine.onSampleBuffer = { sampleBuffer in
            self.hqRecorder.append(sampleBuffer: sampleBuffer)
          }
          try await engine.start()
          await MainActor.run {
            self.systemEngine = engine
            self.lastErrorMessage = ""
            self.startStatusTimer()
            self.isStarting = false
            result(self.currentStatus())
          }
        } else {
          throw AudioEngineError.screenCaptureUnavailable
        }
      } catch {
        await MainActor.run {
          _ = self.hqRecorder.stop()
          self.hqExperimentActive = false
          self.stopAll()
          self.isStarting = false
          self.lastErrorMessage = error.localizedDescription
          result(
            FlutterError(
              code: "hq_start_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func stopHqExperiment(result: @escaping FlutterResult) {
    let stats = hqRecorder.stop()
    hqExperimentActive = false
    stopAll()
    var payload = stats
    payload["status"] = currentStatus()
    result(payload)
  }

  private func pauseHqExperiment(result: @escaping FlutterResult) {
    guard hqExperimentActive, hqRecorder.isRecording else {
      result(
        FlutterError(
          code: "hq_not_running",
          message: "高音質録音が開始されていません。",
          details: nil
        )
      )
      return
    }
    hqRecorder.pause()
    emit(currentStatus())
    result(currentStatus())
  }

  private func resumeHqExperiment(result: @escaping FlutterResult) {
    guard hqExperimentActive, hqRecorder.isRecording else {
      result(
        FlutterError(
          code: "hq_not_running",
          message: "高音質録音が開始されていません。",
          details: nil
        )
      )
      return
    }
    hqRecorder.resume()
    emit(currentStatus())
    result(currentStatus())
  }

  private func discardHqExperiment(result: @escaping FlutterResult) {
    let stats = hqRecorder.discard()
    hqExperimentActive = false
    stopAll()
    var payload = stats
    payload["status"] = currentStatus()
    result(payload)
  }

  /// ミニ画面（会議の最小化／高音質録音）と一番手前表示の切替。
  private func setRecordingWindowMode(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let compact = (args?["compact"] as? Bool) ?? false
    let alwaysOnTop = (args?["alwaysOnTop"] as? Bool) ?? compact
    let width = (args?["width"] as? NSNumber)?.doubleValue ?? 360
    let height = (args?["height"] as? NSNumber)?.doubleValue ?? 220

    DispatchQueue.main.async {
      guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow })
        ?? NSApp.mainWindow
        ?? NSApp.keyWindow
      else {
        result(
          FlutterError(
            code: "no_window",
            message: "ウィンドウを取得できませんでした。",
            details: nil
          )
        )
        return
      }

      if compact {
        if self.savedWindowFrame == nil {
          self.savedWindowFrame = window.frame
          self.savedWindowLevel = window.level
        }
        if !self.compactWindowActive {
          let compactSize = NSSize(width: width, height: height)
          var frame = window.frame
          // 右上付近に寄せて会議アプリを邪魔しにくくする
          if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = visible.maxX - compactSize.width - 24
            frame.origin.y = visible.maxY - compactSize.height - 24
          }
          frame.size = compactSize
          window.setFrame(frame, display: true, animate: true)
          self.compactWindowActive = true
        }
        self.applyAlwaysOnTop(window, enabled: alwaysOnTop)
        window.makeKeyAndOrderFront(nil)
      } else {
        let wasCompact = self.compactWindowActive
        self.compactWindowActive = false
        if let saved = self.savedWindowFrame {
          window.setFrame(saved, display: true, animate: true)
          self.savedWindowFrame = nil
          window.level = self.savedWindowLevel ?? .normal
          self.savedWindowLevel = nil
          window.collectionBehavior.remove(.canJoinAllSpaces)
          window.collectionBehavior.remove(.fullScreenAuxiliary)
        } else if wasCompact {
          let defaultSize = NSSize(width: 1180, height: 820)
          var frame = window.frame
          frame.size = defaultSize
          window.setFrame(frame, display: true, animate: true)
          window.level = self.savedWindowLevel ?? .normal
          self.savedWindowLevel = nil
          window.collectionBehavior.remove(.canJoinAllSpaces)
          window.collectionBehavior.remove(.fullScreenAuxiliary)
        }
      }

      result([
        "compact": compact,
        "alwaysOnTop": alwaysOnTop && compact,
      ])
    }
  }

  private func applyAlwaysOnTop(_ window: NSWindow, enabled: Bool) {
    if enabled {
      window.level = .floating
      window.collectionBehavior.insert(.canJoinAllSpaces)
      window.collectionBehavior.insert(.fullScreenAuxiliary)
    } else {
      window.level = .normal
      window.collectionBehavior.remove(.canJoinAllSpaces)
      window.collectionBehavior.remove(.fullScreenAuxiliary)
    }
  }

  private func revealInFinder(path: String?, result: @escaping FlutterResult) {
    guard let path, !path.isEmpty else {
      result(
        FlutterError(
          code: "invalid_path",
          message: "path が空です。",
          details: nil
        )
      )
      return
    }
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.activateFileViewerSelecting([url])
    result(true)
  }

  private func start(result: @escaping FlutterResult) {
    if hqExperimentActive || hqRecorder.isRecording {
      result(
        FlutterError(
          code: "hq_busy",
          message: "高音質録音実験中です。先に実験を停止してください。",
          details: nil
        )
      )
      return
    }
    if isStarting {
      result(
        FlutterError(
          code: "already_starting",
          message: "音声キャプチャの開始処理中です。",
          details: nil
        )
      )
      return
    }
    isStarting = true

    // Task 本体は self を明示的に強参照。長寿命コールバックも同じ寿命（stopAll で engine を外す）
    // のため [weak self] と混ぜると ImplicitStrongCapture 警告になる。
    Task { [self] in
      var warnings: [String] = []
      do {
        let micGranted = await self.requestMicrophonePermissionAsync()
        guard micGranted else {
          throw AudioEngineError.screenCapture(
            "マイク権限がありません。システム設定で許可してください。"
          )
        }

        self.pcmBridge.start()

        if #available(macOS 13.0, *) {
          let engine = SystemAudioCaptureEngine()
          engine.onActivity = { _, _, _ in
            self.emitThrottled()
          }
          engine.onSampleBuffer = { sampleBuffer in
            if self.hqRecorder.isRecording {
              self.hqRecorder.append(sampleBuffer: sampleBuffer)
            }
            self.pcmBridge.pushSpeakerSampleBuffer(sampleBuffer)
          }
          try await engine.start()
          await MainActor.run {
            self.systemEngine = engine
          }
        } else {
          throw AudioEngineError.screenCaptureUnavailable
        }

        do {
          try self.micEngine.start(
            inputUID: self.selectedInputUID,
            virtualOutputUID: self.selectedVirtualUID
          )
          if !self.micEngine.lastSetupWarning.isEmpty {
            warnings.append(self.micEngine.lastSetupWarning)
          }
        } catch {
          warnings.append(error.localizedDescription)
          self.micEngine.stop()
          NSLog("[OnlineAudio] mic start failed: %@", error.localizedDescription)
        }

        let warningText = warnings.joined(separator: "\n")
        await MainActor.run {
          self.lastErrorMessage = warningText
          self.startStatusTimer()
          self.isStarting = false
          self.resultStatus(result)
        }
      } catch {
        await MainActor.run {
          self.stopAll()
          self.isStarting = false
          self.lastErrorMessage = error.localizedDescription
          result(
            FlutterError(
              code: "start_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func resultStatus(_ result: @escaping FlutterResult) {
    result(currentStatus())
  }

  private func stopAll() {
    statusTimer?.invalidate()
    statusTimer = nil
    pcmStreamingEnabled = false
    pcmBridge.stop()
    micEngine.stop()
    if hqRecorder.isRecording {
      _ = hqRecorder.stop()
    }
    hqExperimentActive = false
    if #available(macOS 13.0, *) {
      (systemEngine as? SystemAudioCaptureEngine)?.stop()
    }
    systemEngine = nil
    emit(currentStatus())
  }

  private func startStatusTimer() {
    statusTimer?.invalidate()
    statusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.emit(self.currentStatus())
    }
  }

  private func emitThrottled() {
    let now = Date().timeIntervalSince1970
    if now - lastEmitAt < 0.15 { return }
    lastEmitAt = now
    emit(currentStatus())
  }

  private func emit(_ status: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(status)
    }
  }

  private func currentStatus() -> [String: Any] {
    stateLock.lock()
    defer { stateLock.unlock() }

    var speakerReceiving = false
    var speakerLevel: Float = 0
    var speakerFrames: Int = 0
    var speakerRunning = false
    if #available(macOS 13.0, *) {
      if let engine = systemEngine as? SystemAudioCaptureEngine {
        speakerReceiving = engine.isReceiving
        speakerLevel = engine.lastLevel
        speakerFrames = Int(clamping: engine.framesReceived)
        speakerRunning = engine.isRunning
      }
    }

    let virtual = AudioDeviceEnumerator.preferredVirtualOutput()
    var status: [String: Any] = [
      "platform": "macos",
      "micRunning": micEngine.isRunning,
      "micHearing": micEngine.isHearing,
      "micLevel": Double(micEngine.lastLevel),
      "micPeak": Double(micEngine.lastPeak),
      "micFrames": Int(clamping: micEngine.framesPassed),
      "micCallbacks": Int(clamping: micEngine.callbackCount),
      "micInputName": micEngine.inputDeviceName,
      "micFormat": micEngine.inputFormatDescription,
      "micDiagnosis": micEngine.captureDiagnosis,
      "virtualOutputName": micEngine.virtualOutputName,
      "micPassthroughEnabled": micEngine.passthroughEnabled,
      "micMuted": micEngine.isMuted,
      "virtualDeviceAvailable": virtual != nil,
      "virtualDeviceName": virtual?.name ?? "",
      "speakerRunning": speakerRunning,
      "speakerReceiving": speakerReceiving,
      "speakerLevel": Double(speakerLevel),
      "speakerFrames": speakerFrames,
      "pcmStreamingEnabled": pcmStreamingEnabled,
      "pcmChunksEmitted": Int(clamping: pcmBridge.chunksEmitted),
      "hqExperimentActive": hqExperimentActive,
      "hqRecording": hqRecorder.isRecording,
      "hqPaused": hqRecorder.isPaused,
      "hqOutputPath": hqRecorder.outputPath,
      "lastError": lastErrorMessage,
    ]
    if let selectedInputUID {
      status["selectedInputUid"] = selectedInputUID
    }
    if let selectedVirtualUID {
      status["selectedVirtualUid"] = selectedVirtualUID
    }
    return status
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    Task {
      let granted = await requestMicrophonePermissionAsync()
      await MainActor.run {
        result(granted)
      }
    }
  }

  private func requestMicrophonePermissionAsync() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  fileprivate func attachEventSink(_ sink: FlutterEventSink?) {
    eventSink = sink
  }

  fileprivate func attachPcmEventSink(_ sink: FlutterEventSink?) {
    pcmEventSink = sink
  }
}

extension OnlineMeetingAudioPlugin: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    attachEventSink(events)
    events(currentStatus())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    attachEventSink(nil)
    return nil
  }
}

private final class PcmStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: OnlineMeetingAudioPlugin?

  init(plugin: OnlineMeetingAudioPlugin) {
    self.plugin = plugin
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    plugin?.attachPcmEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.attachPcmEventSink(nil)
    return nil
  }
}
