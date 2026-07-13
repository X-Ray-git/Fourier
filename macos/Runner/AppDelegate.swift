import Cocoa
import FlutterMacOS
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

    let badgeChannel = FlutterMethodChannel(name: "io.github.xraygit.autofolo/badge", binaryMessenger: controller.engine.binaryMessenger)
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

    let imageChannel = FlutterMethodChannel(name: "io.github.xraygit.autofolo/image_clipboard", binaryMessenger: controller.engine.binaryMessenger)
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

    let cursorChannel = FlutterMethodChannel(name: "io.github.xraygit.autofolo/cursor", binaryMessenger: controller.engine.binaryMessenger)
    cursorChannel.setMethodCallHandler { (call, result) in
      if call.method == "activateZoomInCursor" {
        AutoFoloCursorFactory.zoomInCursor.set()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let windowControlsChannel = FlutterMethodChannel(name: "io.github.xraygit.autofolo/window_controls", binaryMessenger: controller.engine.binaryMessenger)
    windowControlsChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "setTrafficLightsHidden", let hidden = call.arguments as? Bool {
        (self?.mainFlutterWindow as? MainFlutterWindow)?.setTrafficLightsHidden(hidden)
        result(nil)
      } else if call.method == "setTrafficLightsHidden" {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a Boolean", details: nil))
      } else if call.method == "setMovable", let movable = call.arguments as? Bool {
        self?.mainFlutterWindow?.isMovable = movable
        result(nil)
      } else if call.method == "setMovable" {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a Boolean", details: nil))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let webViewControlsChannel = FlutterMethodChannel(name: "io.github.xraygit.autofolo/webview_controls", binaryMessenger: controller.engine.binaryMessenger)
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
}

private enum AutoFoloCursorFactory {
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
