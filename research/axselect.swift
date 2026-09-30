import Cocoa
import ApplicationServices
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Statistics"
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func find(_ e: AXUIElement, _ pred: (AXUIElement) -> Bool) -> AXUIElement? { if pred(e) { return e }; for c in kids(e) { if let r = find(c, pred) { return r } }; return nil }
for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] where (attr(w, kAXTitleAttribute) as? String) == "Settings" {
  guard let table = find(w, { (attr($0, kAXDescriptionAttribute) as? String) == "Category List" }) else { print("no table"); exit(1) }
  for row in kids(table) where (attr(row, kAXRoleAttribute) as? String) == "AXRow" {
    if let cell = kids(row).first, let d = attr(cell, kAXDescriptionAttribute) as? String, d.hasPrefix(target) {
      let r = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue); print("select", d, r.rawValue)
    }
  }
}
