import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private enum Metrics {
    static let windowRadius: CGFloat = 28
    static let trafficLightCenterX: CGFloat = 28
    static let trafficLightCenterYFromTop: CGFloat = 28
    static let trafficLightDiameter: CGFloat = 14
    static let trafficLightCenterSpacing: CGFloat = 23
  }

  private var trafficLightContainer: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = NSColor.clear
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
    guard let contentView = self.contentView else {
      return
    }

    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    let buttonSize = NSSize(
      width: Metrics.trafficLightDiameter,
      height: Metrics.trafficLightDiameter
    )
    let containerSize = NSSize(
      width: Metrics.trafficLightCenterSpacing * 2 + buttonSize.width,
      height: buttonSize.height
    )
    let originY = contentView.isFlipped
      ? Metrics.trafficLightCenterYFromTop - buttonSize.height / 2
      : contentView.bounds.height - Metrics.trafficLightCenterYFromTop - buttonSize.height / 2
    let origin = NSPoint(
      x: Metrics.trafficLightCenterX - buttonSize.width / 2,
      y: originY
    )

    let container: NSView
    if let existingContainer = trafficLightContainer {
      container = existingContainer
    } else {
      let newContainer = NSView(frame: NSRect(origin: origin, size: containerSize))
      newContainer.wantsLayer = false
      addTrafficLightButtons(to: newContainer)
      trafficLightContainer = newContainer
      container = newContainer
    }

    if container.superview !== contentView {
      contentView.addSubview(container, positioned: .above, relativeTo: nil)
    } else {
      container.removeFromSuperview()
      contentView.addSubview(container, positioned: .above, relativeTo: nil)
    }
    container.frame = NSRect(origin: origin, size: containerSize)
    for (index, subview) in container.subviews.enumerated() {
      subview.frame = NSRect(
        x: Metrics.trafficLightCenterSpacing * CGFloat(index),
        y: 0,
        width: Metrics.trafficLightDiameter,
        height: Metrics.trafficLightDiameter
      )
    }
  }

  private func addTrafficLightButtons(to container: NSView) {
    let close = TrafficLightButton(kind: .close) { [weak self] in
      self?.performClose(nil)
    }
    let minimize = TrafficLightButton(kind: .minimize) { [weak self] in
      self?.miniaturize(nil)
    }
    let zoom = TrafficLightButton(kind: .zoom) { [weak self] in
      self?.zoom(nil)
    }

    [close, minimize, zoom].forEach { button in
      button.autoresizingMask = []
      container.addSubview(button)
    }
  }
}

private enum TrafficLightKind {
  case close
  case minimize
  case zoom

  var fillColor: NSColor {
    switch self {
    case .close:
      return NSColor(red: 1.0, green: 0.37, blue: 0.35, alpha: 1)
    case .minimize:
      return NSColor(red: 1.0, green: 0.77, blue: 0.18, alpha: 1)
    case .zoom:
      return NSColor(red: 0.20, green: 0.78, blue: 0.32, alpha: 1)
    }
  }
}

private final class TrafficLightButton: NSControl {
  private let kind: TrafficLightKind
  private let actionHandler: () -> Void
  private var trackingArea: NSTrackingArea?
  private var isHovered = false
  private var isPressed = false

  init(kind: TrafficLightKind, actionHandler: @escaping () -> Void) {
    self.kind = kind
    self.actionHandler = actionHandler
    super.init(frame: .zero)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    isPressed = false
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    isPressed = true
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    let shouldFire = bounds.contains(location)
    isPressed = false
    needsDisplay = true
    if shouldFire {
      actionHandler()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    let circleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(ovalIn: circleRect)
    let activeColor = kind.fillColor
    let color = isPressed
      ? activeColor.blended(withFraction: 0.18, of: .black) ?? activeColor
      : activeColor
    color.setFill()
    path.fill()

    NSColor.black.withAlphaComponent(0.12).setStroke()
    path.lineWidth = 0.5
    path.stroke()

    if isHovered {
      drawSymbol(in: circleRect)
    }
  }

  private func drawSymbol(in rect: NSRect) {
    NSColor.black.withAlphaComponent(0.56).setStroke()
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 1.15

    switch kind {
    case .close:
      path.move(to: NSPoint(x: rect.minX + 4.2, y: rect.minY + 4.2))
      path.line(to: NSPoint(x: rect.maxX - 4.2, y: rect.maxY - 4.2))
      path.move(to: NSPoint(x: rect.minX + 4.2, y: rect.maxY - 4.2))
      path.line(to: NSPoint(x: rect.maxX - 4.2, y: rect.minY + 4.2))
    case .minimize:
      path.move(to: NSPoint(x: rect.minX + 3.8, y: rect.midY))
      path.line(to: NSPoint(x: rect.maxX - 3.8, y: rect.midY))
    case .zoom:
      path.move(to: NSPoint(x: rect.midX, y: rect.minY + 3.6))
      path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 3.6))
      path.move(to: NSPoint(x: rect.minX + 3.6, y: rect.midY))
      path.line(to: NSPoint(x: rect.maxX - 3.6, y: rect.midY))
    }

    path.stroke()
  }
}
