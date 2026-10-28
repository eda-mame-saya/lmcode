import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var onlineMeetingAudioPlugin: OnlineMeetingAudioPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 修正点：起動時サイズを 800x600 からやや大きく（全画面にはしない）
    let defaultSize = NSSize(width: 1180, height: 820)
    setContentSize(defaultSize)
    center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    onlineMeetingAudioPlugin = OnlineMeetingAudioPlugin(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
