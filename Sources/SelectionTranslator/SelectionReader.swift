import AppKit
import ApplicationServices

enum SelectionReaderError: LocalizedError {
    case accessibilityPermissionMissing
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "缺少辅助功能权限。"
        case .noSelectedText:
            return "未检测到选中文本。"
        }
    }
}

final class SelectionReader {
    private let pasteboard = NSPasteboard.general

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func readSelectedText() async throws -> String {
        guard isAccessibilityTrusted(prompt: false) else {
            throw SelectionReaderError.accessibilityPermissionMissing
        }

        let originalItems = clonePasteboardItems(pasteboard.pasteboardItems ?? [])
        let originalChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        sendCopyShortcut()

        let copiedText = await waitForCopiedString(after: originalChangeCount)
        restorePasteboardItems(originalItems)

        guard let copiedText, !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionReaderError.noSelectedText
        }

        return copiedText
    }

    private func sendCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    @MainActor
    private func waitForCopiedString(after changeCount: Int) async -> String? {
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 75_000_000)
            if pasteboard.changeCount != changeCount, let value = pasteboard.string(forType: .string) {
                return value
            }
        }
        return pasteboard.string(forType: .string)
    }

    private func clonePasteboardItems(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboardItems(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
