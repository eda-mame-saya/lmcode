import CoreAudio
import Foundation

struct AudioDeviceInfo: Sendable {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let isInput: Bool
  let isOutput: Bool
  let isVirtualCandidate: Bool
  let isDefaultInput: Bool
  let isDefaultOutput: Bool

  var asDictionary: [String: Any] {
    [
      "id": id,
      "uid": uid,
      "name": name,
      "isInput": isInput,
      "isOutput": isOutput,
      "isVirtualCandidate": isVirtualCandidate,
      "isDefaultInput": isDefaultInput,
      "isDefaultOutput": isDefaultOutput,
    ]
  }
}

enum AudioDeviceEnumerator {
  private static let virtualNameHints = ["blackhole", "meeting assist", "soundflower", "loopback"]

  static func listDevices() -> [AudioDeviceInfo] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize
    ) == noErr else {
      return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &deviceIDs
    ) == noErr else {
      return []
    }

    let defaultInput = defaultInputDeviceID()
    let defaultOutput = defaultOutputDeviceID()

    return deviceIDs.compactMap { deviceID in
      let name = stringProperty(deviceID, selector: kAudioObjectPropertyName) ?? "Device \(deviceID)"
      let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
      let inputChannels = channelCount(deviceID, scope: kAudioDevicePropertyScopeInput)
      let outputChannels = channelCount(deviceID, scope: kAudioDevicePropertyScopeOutput)
      guard inputChannels > 0 || outputChannels > 0 else { return nil }
      let lowered = name.lowercased()
      let isVirtual = virtualNameHints.contains { lowered.contains($0) }
      return AudioDeviceInfo(
        id: deviceID,
        uid: uid,
        name: name,
        isInput: inputChannels > 0,
        isOutput: outputChannels > 0,
        isVirtualCandidate: isVirtual,
        isDefaultInput: defaultInput == deviceID,
        isDefaultOutput: defaultOutput == deviceID
      )
    }
  }

  static func defaultInputDeviceID() -> AudioDeviceID? {
    deviceID(for: kAudioHardwarePropertyDefaultInputDevice)
  }

  static func defaultOutputDeviceID() -> AudioDeviceID? {
    deviceID(for: kAudioHardwarePropertyDefaultOutputDevice)
  }

  /// LMCode 仮想マイクフォークを最優先し、次に BlackHole 等の既存仮想出力。
  static func preferredVirtualOutput() -> AudioDeviceInfo? {
    let outputs = listDevices().filter { $0.isVirtualCandidate && $0.isOutput }
    if outputs.isEmpty { return nil }
    func score(_ name: String) -> Int {
      let n = name.lowercased()
      if n.contains("meeting assist") { return 0 }
      if n.contains("blackhole") { return 1 }
      if n.contains("soundflower") || n.contains("loopback") { return 2 }
      return 3
    }
    return outputs.sorted { score($0.name) < score($1.name) }.first
  }

  static func preferredPhysicalInput(excludingVirtualUID uid: String?) -> AudioDeviceInfo? {
    let devices = listDevices().filter { $0.isInput }
    if let uid,
       let match = devices.first(where: { $0.uid == uid && !$0.isVirtualCandidate }) {
      return match
    }
    if let defaultID = defaultInputDeviceID(),
       let match = devices.first(where: { $0.id == defaultID && !$0.isVirtualCandidate }) {
      return match
    }
    return devices.first { !$0.isVirtualCandidate }
  }

  private static func deviceID(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    return status == noErr ? deviceID : nil
  }

  private static func stringProperty(
    _ deviceID: AudioDeviceID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
    }
    guard status == noErr else { return nil }
    return value as String
  }

  private static func channelCount(
    _ deviceID: AudioDeviceID,
    scope: AudioObjectPropertyScope
  ) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
          dataSize > 0 else {
      return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
      return 0
    }
    let bufferList = raw.assumingMemoryBound(to: AudioBufferList.self)
    var channels = 0
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    for buffer in buffers {
      channels += Int(buffer.mNumberChannels)
    }
    return channels
  }
}
