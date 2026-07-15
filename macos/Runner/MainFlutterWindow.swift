import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var trafficLightsHidden = false
  private var trafficLightContainer: TrafficLightContainer?

  private enum Metrics {
    static let windowRadius: CGFloat = 24
    static let trafficLightCenterX: CGFloat = 24
    static let trafficLightCenterYFromTop: CGFloat = 24
    static let trafficLightDiameter: CGFloat = 14
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

  override func becomeKey() {
    super.becomeKey()
    trafficLightContainer?.setWindowActive(true)
  }

  override func resignKey() {
    super.resignKey()
    trafficLightContainer?.setWindowActive(false)
  }

  private func scheduleTrafficLightPositioning() {
    positionTrafficLights()
    DispatchQueue.main.async { [weak self] in
      self?.positionTrafficLights()
    }
  }

  private func positionTrafficLights() {
    guard let contentView else {
      return
    }

    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .forEach { standardWindowButton($0)?.isHidden = true }

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

    let container: TrafficLightContainer
    if let trafficLightContainer {
      container = trafficLightContainer
    } else {
      container = makeTrafficLightContainer(frame: NSRect(origin: origin, size: containerSize))
      trafficLightContainer = container
      contentView.addSubview(container, positioned: .above, relativeTo: nil)
    }

    if container.superview !== contentView {
      container.removeFromSuperview()
      contentView.addSubview(container, positioned: .above, relativeTo: nil)
    }
    container.frame = NSRect(origin: origin, size: containerSize)
    container.isHidden = trafficLightsHidden
    if trafficLightsHidden {
      container.setGroupHovered(false)
    }
    container.setWindowActive(isKeyWindow)
  }

  private func makeTrafficLightContainer(frame: NSRect) -> TrafficLightContainer {
    let container = TrafficLightContainer(frame: frame)
    let configurations: [(TrafficLightKind, NSWindow.ButtonType)] = [
      (.close, .closeButton),
      (.minimize, .miniaturizeButton),
      (.zoom, .zoomButton),
    ]

    for (index, configuration) in configurations.enumerated() {
      let button = TrafficLightButton(kind: configuration.0) { [weak self] in
        self?.performStandardWindowButton(configuration.1)
      }
      button.frame = NSRect(
        x: Metrics.trafficLightCenterSpacing * CGFloat(index),
        y: 0,
        width: Metrics.trafficLightDiameter,
        height: Metrics.trafficLightDiameter
      )
      container.addTrafficLight(button)
    }
    return container
  }

  private func performStandardWindowButton(_ type: NSWindow.ButtonType) {
    guard let button = standardWindowButton(type),
          let action = button.action else {
      return
    }
    NSApp.sendAction(action, to: button.target, from: button)
  }

  func setTrafficLightsHidden(_ hidden: Bool) {
    trafficLightsHidden = hidden
    positionTrafficLights()
  }
}

private enum TrafficLightKind {
  case close
  case minimize
  case zoom

  var activeColor: NSColor {
    switch self {
    case .close:
      return NSColor(red: 1.0, green: 0.373, blue: 0.341, alpha: 1)
    case .minimize:
      return NSColor(red: 1.0, green: 0.741, blue: 0.180, alpha: 1)
    case .zoom:
      return NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .close:
      return "Close"
    case .minimize:
      return "Minimize"
    case .zoom:
      return "Enter Full Screen"
    }
  }
}

private final class TrafficLightContainer: NSView {
  private var trafficLights: [TrafficLightButton] = []
  private var hoveredTrafficLights: Set<ObjectIdentifier> = []

  override var mouseDownCanMoveWindow: Bool { false }

  func addTrafficLight(_ button: TrafficLightButton) {
    button.onHoverChanged = { [weak self] button, hovered in
      self?.updateHover(for: button, hovered: hovered)
    }
    trafficLights.append(button)
    addSubview(button)
  }

  func setWindowActive(_ active: Bool) {
    trafficLights.forEach { $0.setWindowActive(active) }
  }

  func setGroupHovered(_ hovered: Bool) {
    if !hovered {
      hoveredTrafficLights.removeAll()
    }
    trafficLights.forEach { $0.setGroupHovered(hovered) }
  }

  private func updateHover(for button: TrafficLightButton, hovered: Bool) {
    let identifier = ObjectIdentifier(button)
    if hovered {
      hoveredTrafficLights.insert(identifier)
    } else {
      hoveredTrafficLights.remove(identifier)
    }
    let groupHovered = !hoveredTrafficLights.isEmpty
    trafficLights.forEach { $0.setGroupHovered(groupHovered) }
  }
}

private final class TrafficLightButton: NSControl {
  private let kind: TrafficLightKind
  private let actionHandler: () -> Void
  private var trackingArea: NSTrackingArea?
  private var windowActive = false
  private var groupHovered = false
  private var pressed = false
  var onHoverChanged: ((TrafficLightButton, Bool) -> Void)?

  override var mouseDownCanMoveWindow: Bool { false }

  init(kind: TrafficLightKind, actionHandler: @escaping () -> Void) {
    self.kind = kind
    self.actionHandler = actionHandler
    super.init(frame: .zero)
    setAccessibilityRole(.button)
    setAccessibilityLabel(kind.accessibilityLabel)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let newArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(newArea)
    trackingArea = newArea
  }

  override func mouseEntered(with event: NSEvent) {
    onHoverChanged?(self, true)
  }

  override func mouseExited(with event: NSEvent) {
    onHoverChanged?(self, false)
  }

  func setWindowActive(_ active: Bool) {
    guard windowActive != active else { return }
    windowActive = active
    needsDisplay = true
  }

  func setGroupHovered(_ hovered: Bool) {
    guard groupHovered != hovered else { return }
    groupHovered = hovered
    if !hovered {
      pressed = false
    }
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    pressed = true
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    let isInside = bounds.contains(location)
    guard pressed != isInside else { return }
    pressed = isInside
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    let shouldFire = pressed && bounds.contains(location)
    pressed = false
    needsDisplay = true
    if shouldFire {
      actionHandler()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    let circleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(ovalIn: circleRect)
    let baseColor = windowActive ? kind.activeColor : inactiveColor
    let fillColor = pressed
      ? baseColor.blended(withFraction: 0.18, of: .black) ?? baseColor
      : baseColor

    fillColor.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(windowActive ? 0.14 : 0.08).setStroke()
    path.lineWidth = 0.5
    path.stroke()

    if groupHovered {
      drawSymbol(in: circleRect)
    }
  }

  private var inactiveColor: NSColor {
    NSColor(name: nil) { appearance in
      let match = appearance.bestMatch(from: [.darkAqua, .aqua])
      return match == .darkAqua
        ? NSColor(white: 0.34, alpha: 1)
        : NSColor(white: 0.76, alpha: 1)
    }
  }

  private func drawSymbol(in rect: NSRect) {
    NSColor.black.withAlphaComponent(windowActive ? 0.58 : 0.42).setStroke()
    NSColor.black.withAlphaComponent(windowActive ? 0.58 : 0.42).setFill()

    switch kind {
    case .close:
      let path = symbolPath()
      path.move(to: NSPoint(x: rect.minX + 4.0, y: rect.minY + 4.0))
      path.line(to: NSPoint(x: rect.maxX - 4.0, y: rect.maxY - 4.0))
      path.move(to: NSPoint(x: rect.minX + 4.0, y: rect.maxY - 4.0))
      path.line(to: NSPoint(x: rect.maxX - 4.0, y: rect.minY + 4.0))
      path.stroke()
    case .minimize:
      let path = symbolPath()
      path.move(to: NSPoint(x: rect.minX + 3.8, y: rect.midY))
      path.line(to: NSPoint(x: rect.maxX - 3.8, y: rect.midY))
      path.stroke()
    case .zoom:
      drawZoomSymbol(in: rect)
    }
  }

  private func symbolPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 1.6
    return path
  }

  private func drawZoomSymbol(in rect: NSRect) {
    let upperLeft = NSBezierPath()
    upperLeft.move(to: NSPoint(x: rect.minX + 3.5, y: rect.maxY - 3.5))
    upperLeft.line(to: NSPoint(x: rect.minX + 7.7, y: rect.maxY - 3.5))
    upperLeft.line(to: NSPoint(x: rect.minX + 3.5, y: rect.maxY - 7.7))
    upperLeft.close()
    upperLeft.fill()

    let lowerRight = NSBezierPath()
    lowerRight.move(to: NSPoint(x: rect.maxX - 3.5, y: rect.minY + 3.5))
    lowerRight.line(to: NSPoint(x: rect.maxX - 7.7, y: rect.minY + 3.5))
    lowerRight.line(to: NSPoint(x: rect.maxX - 3.5, y: rect.minY + 7.7))
    lowerRight.close()
    lowerRight.fill()
  }
}
