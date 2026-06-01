import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let visualEffectView = NSVisualEffectView(frame: flutterViewController.view.bounds)
    visualEffectView.autoresizingMask = [.width, .height]
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.material = .sidebar
    visualEffectView.state = .active

    flutterViewController.view.wantsLayer = true
    flutterViewController.view.layer?.backgroundColor = NSColor.clear.cgColor
    flutterViewController.view.addSubview(visualEffectView, positioned: .below, relativeTo: nil)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
