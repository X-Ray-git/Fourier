import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private enum Metrics {
    static let windowRadius: CGFloat = 24
    static let trafficLightCenterX: CGFloat = 24
    static let trafficLightCenterYFromTop: CGFloat = 24
    static let trafficLightCenterSpacing: CGFloat = 23
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = NSColor.clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let visualEffectView = NSVisualEffectView(frame: flutterViewController.view.bounds)
    visualEffectView.autoresizingMask = [.width, .height]
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.material = .sidebar
    visualEffectView.state = .active
    visualEffectView.wantsLayer = true
    visualEffectView.layer?.cornerRadius = Metrics.windowRadius
    visualEffectView.layer?.masksToBounds = true

    flutterViewController.view.wantsLayer = true
    flutterViewController.view.layer?.backgroundColor = NSColor.clear.cgColor
    if let contentView = self.contentView {
      contentView.addSubview(visualEffectView, positioned: .below, relativeTo: flutterViewController.view)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    scheduleTrafficLightPositioning()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    scheduleTrafficLightPositioning()
  }

  private func scheduleTrafficLightPositioning() {
    positionTrafficLights()
    DispatchQueue.main.async { [weak self] in
      self?.positionTrafficLights()
    }
  }

  private func positionTrafficLights() {
    positionStandardWindowButtons()
  }

  private func positionStandardWindowButtons() {
    guard let contentView = self.contentView,
          let close = standardWindowButton(.closeButton),
          let minimize = standardWindowButton(.miniaturizeButton),
          let zoom = standardWindowButton(.zoomButton) else {
      return
    }

    let buttons = [close, minimize, zoom]
    buttons.forEach { $0.isHidden = false }

    let buttonSize = close.frame.size
    let originY = contentView.isFlipped
      ? Metrics.trafficLightCenterYFromTop - buttonSize.height / 2
      : contentView.bounds.height - Metrics.trafficLightCenterYFromTop - buttonSize.height / 2

    for (index, button) in buttons.enumerated() {
      let originInContentView = NSPoint(
        x: Metrics.trafficLightCenterX
          - buttonSize.width / 2
          + Metrics.trafficLightCenterSpacing * CGFloat(index),
        y: originY
      )
      if let buttonSuperview = button.superview {
        let rect = NSRect(origin: originInContentView, size: button.frame.size)
        button.frame.origin = buttonSuperview.convert(rect, from: contentView).origin
      }
    }
  }
}
