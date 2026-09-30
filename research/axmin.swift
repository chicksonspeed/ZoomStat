import Cocoa
let v = CommandLine.arguments[1] == "1"
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
var ws: AnyObject?; AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &ws)
for w in (ws as? [AXUIElement]) ?? [] { var t: AnyObject?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
 if (t as? String) == "Settings" { print(AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, (v ? kCFBooleanTrue : kCFBooleanFalse)!).rawValue) } }
