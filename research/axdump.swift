import Cocoa
import ApplicationServices
// Read-only AX tree dumper for Zoom. Usage: axdump [windowTitleSubstring] [maxDepth]
let args = CommandLine.arguments
let filter = args.count > 1 ? args[1] : ""
let maxDepth = args.count > 2 ? Int(args[2]) ?? 30 : 30
print("AXIsProcessTrusted:", AXIsProcessTrusted())
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first else { print("zoom not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax, 1.0)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func str(_ e: AXUIElement, _ a: String) -> String { if let v = attr(e, a) { return "\(v)".replacingOccurrences(of: "\n", with: "\\n") } ; return "" }
func dump(_ e: AXUIElement, _ d: Int) {
  if d > maxDepth { return }
  let role = str(e, kAXRoleAttribute), title = str(e, kAXTitleAttribute), val = str(e, kAXValueAttribute), desc = str(e, kAXDescriptionAttribute), ident = str(e, kAXIdentifierAttribute)
  print(String(repeating: "  ", count: d) + "\(role) t=\(title) v=\(val.prefix(120)) d=\(desc) id=\(ident)")
  for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { dump(c, d + 1) }
}
for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
  let t = str(w, kAXTitleAttribute)
  if filter.isEmpty || t.contains(filter) { print("=== WINDOW \(t)"); dump(w, 0) }
}
