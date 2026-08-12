import Cocoa
import FlutterMacOS
import Darwin
import WebKit
import webview_flutter_wkwebview

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var isQuitting = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    isQuitting = true
    return .terminateNow
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if isQuitting {
      return true
    }
    sender.orderOut(nil)
    return false
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    mainFlutterWindow?.delegate = self

    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController

    let energyDiagnosticsChannel = FlutterMethodChannel(
      name: "io.github.xraygit.fourier/energy_diagnostics",
      binaryMessenger: controller.engine.binaryMessenger
    )
    energyDiagnosticsChannel.setMethodCallHandler { [weak self] (call, result) in
      guard call.method == "getProcessMetrics" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.processMetrics() ?? [:])
    }

    let badgeChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/badge", binaryMessenger: controller.engine.binaryMessenger)
    badgeChannel.setMethodCallHandler { (call, result) in
      if call.method == "updateBadge" {
        if let args = call.arguments as? [String: Any], let count = args["count"] as? Int {
          NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
        }
      } else if call.method == "removeBadge" {
        NSApp.dockTile.badgeLabel = nil
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let imageChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/image_clipboard", binaryMessenger: controller.engine.binaryMessenger)
    imageChannel.setMethodCallHandler { (call, result) in
      if call.method == "copyImage" {
        if let typedData = call.arguments as? FlutterStandardTypedData {
          let image = NSImage(data: typedData.data)
          if let img = image {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
            result(true)
          } else {
            result(FlutterError(code: "INVALID_IMAGE", message: "Failed to create NSImage from data", details: nil))
          }
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected FlutterStandardTypedData", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let cursorChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/cursor", binaryMessenger: controller.engine.binaryMessenger)
    cursorChannel.setMethodCallHandler { (call, result) in
      if call.method == "activateZoomInCursor" {
        FourierCursorFactory.zoomInCursor.set()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let appMenuChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/app_menu", binaryMessenger: controller.engine.binaryMessenger)
    appMenuChannel.setMethodCallHandler { (call, result) in
      guard call.method == "setItemStates" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let items = call.arguments as? [[String: Any]] else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected menu state items", details: nil))
        return
      }
      DispatchQueue.main.async {
        for item in items {
          guard let path = item["path"] as? [String],
                let selected = item["selected"] as? Bool,
                let menuItem = Self.menuItem(at: path) else {
            continue
          }
          menuItem.state = selected ? .on : .off
        }
      }
      result(nil)
    }

    let windowControlsChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/window_controls", binaryMessenger: controller.engine.binaryMessenger)
    windowControlsChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "setTrafficLightsHidden", let hidden = call.arguments as? Bool {
        (self?.mainFlutterWindow as? MainFlutterWindow)?.setTrafficLightsHidden(hidden)
        result(nil)
      } else if call.method == "setTrafficLightsHidden" {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a Boolean", details: nil))
      } else if call.method == "setAppearance", let mode = call.arguments as? String {
        let appearance: NSAppearance?
        switch mode {
        case "light":
          appearance = NSAppearance(named: .aqua)
        case "dark":
          appearance = NSAppearance(named: .darkAqua)
        case "system":
          appearance = nil
        default:
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected system, light, or dark", details: nil))
          return
        }
        NSApp.appearance = appearance
        self?.mainFlutterWindow?.appearance = appearance
        result(nil)
      } else if call.method == "setSidebarGlassGeometry",
                let args = call.arguments as? [String: Any],
                let width = args["width"] as? NSNumber,
                let margin = args["margin"] as? NSNumber,
                let radius = args["radius"] as? NSNumber {
        (self?.mainFlutterWindow as? MainFlutterWindow)?.setSidebarGlassGeometry(
          width: CGFloat(truncating: width),
          margin: CGFloat(truncating: margin),
          radius: CGFloat(truncating: radius)
        )
        result(nil)
      } else if call.method == "setSidebarGlassGeometry" {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected width, margin, and radius", details: nil))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let webViewControlsChannel = FlutterMethodChannel(name: "io.github.xraygit.fourier/webview_controls", binaryMessenger: controller.engine.binaryMessenger)
    webViewControlsChannel.setMethodCallHandler { [weak controller] (call, result) in
      guard call.method == "enableElementFullscreen" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(macOS 12.3, *) else {
        result(FlutterError(code: "UNAVAILABLE", message: "Element fullscreen requires macOS 12.3 or later", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let identifier = args["webViewIdentifier"] as? Int64,
            let registry = controller,
            let webView = FWFWebViewFlutterWKWebViewExternalAPI.webView(
              forIdentifier: identifier,
              withPluginRegistry: registry
            ) else {
        result(FlutterError(code: "WEBVIEW_NOT_FOUND", message: "Unable to resolve WKWebView", details: nil))
        return
      }
      webView.configuration.preferences.isElementFullscreenEnabled = true
      result(nil)
    }
  }

  private func processMetrics() -> [String: Any] {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let userSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let systemSeconds = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000

    var taskInfo = mach_task_basic_info()
    var taskInfoCount = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let taskInfoResult = withUnsafeMutablePointer(to: &taskInfo) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(taskInfoCount)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &taskInfoCount)
      }
    }

    let window = mainFlutterWindow
    let lowPowerMode: Bool
    if #available(macOS 12.0, *) {
      lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    } else {
      lowPowerMode = false
    }
    var metrics: [String: Any] = [
      "cpuSeconds": userSeconds + systemSeconds,
      "lowPowerMode": lowPowerMode,
      "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
      "appActive": NSApp.isActive,
      "windowVisible": window?.isVisible ?? false,
      "windowMiniaturized": window?.isMiniaturized ?? false,
    ]
    if taskInfoResult == KERN_SUCCESS {
      metrics["residentBytes"] = Int64(taskInfo.resident_size)
    }
    return metrics
  }

  private static func menuItem(at path: [String]) -> NSMenuItem? {
    guard !path.isEmpty, let mainMenu = NSApp.mainMenu else { return nil }
    var currentMenu = mainMenu
    var currentItem: NSMenuItem?
    for title in path {
      currentItem = currentMenu.items.first { $0.title == title }
      guard let item = currentItem else { return nil }
      if title != path.last {
        guard let submenu = item.submenu else { return nil }
        currentMenu = submenu
      }
    }
    return currentItem
  }
}

private enum FourierCursorFactory {
  static let zoomInCursor: NSCursor = {
    if #available(macOS 15.0, *) {
      return NSCursor.zoomIn
    }
    return makeLegacyZoomInCursor()
  }()

  private static func makeLegacyZoomInCursor() -> NSCursor {
    let size = NSSize(width: 28, height: 28)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let lensRect = NSRect(x: 3.5, y: 10.5, width: 14, height: 14)
    let lensPath = NSBezierPath(ovalIn: lensRect)
    NSColor.white.withAlphaComponent(0.92).setFill()
    lensPath.fill()
    NSColor.black.withAlphaComponent(0.78).setStroke()
    lensPath.lineWidth = 1.7
    lensPath.stroke()

    let handle = NSBezierPath()
    handle.lineCapStyle = .round
    handle.lineWidth = 2.4
    handle.move(to: NSPoint(x: 15.0, y: 11.0))
    handle.line(to: NSPoint(x: 23.0, y: 3.0))
    NSColor.black.withAlphaComponent(0.78).setStroke()
    handle.stroke()

    let plus = NSBezierPath()
    plus.lineCapStyle = .round
    plus.lineWidth = 1.5
    plus.move(to: NSPoint(x: 8.0, y: 17.5))
    plus.line(to: NSPoint(x: 13.0, y: 17.5))
    plus.move(to: NSPoint(x: 10.5, y: 15.0))
    plus.line(to: NSPoint(x: 10.5, y: 20.0))
    NSColor.black.withAlphaComponent(0.78).setStroke()
    plus.stroke()

    return NSCursor(image: image, hotSpot: NSPoint(x: 10.5, y: 10.5))
  }
}
