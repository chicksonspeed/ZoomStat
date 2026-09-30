import Cocoa
import ApplicationServices
let target = CommandLine.arguments[1]
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func find(_ e: AXUIElement, _ pred: (AXUIElement) -> Bool) -> AXUIElement? { if pred(e) { return e }; for c in kids(e) { if let r = find(c, pred) { return r } }; return nil }
for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] where (attr(w, kAXTitleAttribute) as? String) == "Settings" {
  if let t = find(w, { (attr($0, kAXRoleAttribute) as? String) == "Tab" && ((attr($0, kAXTitleAttribute) as? String) ?? "").hasPrefix(target) }) {
    var names: CFArray?; AXUIElementCopyActionNames(t, &names); print("actions", names as Any)
    print("press", AXUIElementPerformAction(t, kAXPressAction as CFString).rawValue)
  } else { print("not found") }
}
