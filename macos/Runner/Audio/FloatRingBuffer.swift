import Foundation

/// Lock-free-ish single-producer / single-consumer float ring buffer for mic passthrough.
final class FloatRingBuffer: @unchecked Sendable {
  private let capacity: Int
  private var storage: [Float]
  private var writeIndex = 0
  private var readIndex = 0
  private let lock = NSLock()

  init(capacity: Int) {
    self.capacity = max(capacity, 1024)
    storage = [Float](repeating: 0, count: self.capacity)
  }

  func reset() {
    lock.lock()
    writeIndex = 0
    readIndex = 0
    lock.unlock()
  }

  @discardableResult
  func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
    guard count > 0 else { return 0 }
    lock.lock()
    defer { lock.unlock() }
    var written = 0
    while written < count {
      let next = (writeIndex + 1) % capacity
      if next == readIndex {
        break
      }
      storage[writeIndex] = source[written]
      writeIndex = next
      written += 1
    }
    return written
  }

  @discardableResult
  func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
    guard count > 0 else { return 0 }
    lock.lock()
    defer { lock.unlock() }
    var read = 0
    while read < count && readIndex != writeIndex {
      destination[read] = storage[readIndex]
      readIndex = (readIndex + 1) % capacity
      read += 1
    }
    if read < count {
      for i in read..<count {
        destination[i] = 0
      }
    }
    return read
  }
}
