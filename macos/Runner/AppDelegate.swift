import Cocoa
import FlutterMacOS

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

    let badgeChannel = FlutterMethodChannel(name: "com.autofolo/badge", binaryMessenger: controller.engine.binaryMessenger)
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

    let imageChannel = FlutterMethodChannel(name: "com.autofolo/image_clipboard", binaryMessenger: controller.engine.binaryMessenger)
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
  }
}
