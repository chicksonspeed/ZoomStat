import ApplicationServices
import AppKit

/// Minimal read-mostly wrappers around the Accessibility C API.
enum AX {
    static func attr<T>(_ e: AXUIElement, _ name: String, as: T.Type = T.self) -> T? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? { attr(e, name, as: String.self) }
    static func role(_ e: AXUIElement) -> String? { string(e, kAXRoleAttribute) }
    static func title(_ e: AXUIElement) -> String? { string(e, kAXTitleAttribute) }
    static func desc(_ e: AXUIElement) -> String? { string(e, kAXDescriptionAttribute) }
    static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute, as: [AXUIElement].self) ?? [] }
    static func windows(_ app: AXUIElement) -> [AXUIElement] { attr(app, kAXWindowsAttribute, as: [AXUIElement].self) ?? [] }

    /// Visible text of an element: Zoom puts it in AXDescription; fall back to value/title.
    static func text(_ e: AXUIElement) -> String? {
        for a in [kAXDescriptionAttribute, kAXValueAttribute, kAXTitleAttribute] {
            if let s = string(e, a), !s.isEmpty { return s }
        }
        return nil
    }

    static func find(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 12, _ pred: (AXUIElement) -> Bool) -> AXUIElement? {
        if pred(e) { return e }
        guard depth < maxDepth else { return nil }
        for c in children(e) { if let r = find(c, depth: depth + 1, maxDepth: maxDepth, pred) { return r } }
        return nil
    }

    static func findAll(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 12, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
        var out: [AXUIElement] = []
        if pred(e) { out.append(e) }
        guard depth < maxDepth else { return out }
        for c in children(e) { out += findAll(c, depth: depth + 1, maxDepth: maxDepth, pred) }
        return out
    }

    /// Text of leaf static-text elements in document order.
    static func leafTexts(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 12) -> [String] {
        let kids = children(e)
        if kids.isEmpty {
            if role(e) == kAXStaticTextRole as String, let t = text(e) { return [t] }
            return []
        }
        guard depth < maxDepth else { return [] }
        return kids.flatMap { leafTexts($0, depth: depth + 1, maxDepth: maxDepth) }
    }

    @discardableResult
    static func press(_ e: AXUIElement) -> Bool { AXUIElementPerformAction(e, kAXPressAction as CFString) == .success }

    @discardableResult
    static func set(_ e: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(e, name as CFString, value) == .success
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
