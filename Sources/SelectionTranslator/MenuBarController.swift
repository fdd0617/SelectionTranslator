import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    init(
        onTranslate: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Selection Translator")

        let menu = NSMenu()
        menu.addItem(MenuActionItem(title: "翻译选区", keyEquivalent: "", actionHandler: onTranslate))
        menu.addItem(MenuActionItem(title: "设置...", keyEquivalent: ",", actionHandler: onSettings))
        menu.addItem(MenuActionItem(title: "请求辅助功能权限", keyEquivalent: "", actionHandler: onRequestAccessibility))
        menu.addItem(.separator())
        menu.addItem(MenuActionItem(title: "退出", keyEquivalent: "q", actionHandler: onQuit))
        statusItem.menu = menu
    }
}

@MainActor
final class MenuActionItem: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, keyEquivalent: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }
}
