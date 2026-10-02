import AppKit
import ApplicationServices

enum HotkeyAccessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (once per call site) to grant Accessibility so global ⌃⌥N works.
    @discardableResult
    static func requestTrustIfNeeded(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
