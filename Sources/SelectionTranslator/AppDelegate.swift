import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keychain = KeychainStore()
    private let selectionReader = SelectionReader()
    private let translator = OpenAITranslator()
    private let panelController = FloatingPanelController()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKeyManager: HotKeyManager?
    private var selectionMonitor: SelectionMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationMenu.install()
        settingsWindowController = SettingsWindowController(keychain: keychain)
        menuBarController = MenuBarController(
            onTranslate: { [weak self] in self?.translateSelection() },
            onSettings: { [weak self] in self?.showSettings() },
            onRequestAccessibility: { [weak self] in self?.requestAccessibilityPermission() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        do {
            hotKeyManager = try HotKeyManager(keyCode: UInt32(kVK_Space), modifiers: optionKey) { [weak self] in
                self?.translateSelection()
            }
        } catch {
            panelController.showError(
                message: "快捷键注册失败",
                detail: error.localizedDescription,
                actionTitle: nil,
                action: nil
            )
        }

        selectionMonitor = SelectionMonitor { [weak self] in
            self?.translateSelection(isAutomatic: true)
        }

        _ = selectionReader.isAccessibilityTrusted(prompt: false)
    }

    private func translateSelection(isAutomatic: Bool = false) {
        Task { @MainActor in
            guard selectionReader.isAccessibilityTrusted(prompt: true) else {
                if isAutomatic { return }
                panelController.showError(
                    message: "无法读取选区",
                    detail: "请在系统设置中允许辅助功能权限。",
                    actionTitle: "重新检查",
                    action: { [weak self] in self?.requestAccessibilityPermission() }
                )
                return
            }

            guard let apiKey = keychain.readAPIKey(), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if isAutomatic { return }
                panelController.showError(
                    message: "请先配置 API Key",
                    detail: nil,
                    actionTitle: "打开设置",
                    action: { [weak self] in self?.showSettings() }
                )
                return
            }

            do {
                let selectedText = try await selectionReader.readSelectedText()
                guard SelectionContentFilter.shouldTranslate(selectedText) else {
                    return
                }

                panelController.showLoading(message: "正在翻译...")

                let translatedText = try await translator.translateToChinese(
                    selectedText,
                    apiURL: UserDefaults.standard.string(forKey: SettingsKeys.apiURL) ?? OpenAITranslator.defaultAPIURL,
                    apiKey: apiKey,
                    model: UserDefaults.standard.string(forKey: SettingsKeys.model) ?? OpenAITranslator.defaultModel
                )

                panelController.showTranslation(
                    translation: translatedText,
                    original: selectedText,
                    onRetry: { [weak self] in self?.translateSelection() }
                )
            } catch {
                if case SelectionReaderError.noSelectedText = error {
                    return
                }

                panelController.showError(
                    message: "翻译失败",
                    detail: error.localizedDescription,
                    actionTitle: "重试",
                    action: { [weak self] in self?.translateSelection() }
                )
            }
        }
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    private func requestAccessibilityPermission() {
        _ = selectionReader.isAccessibilityTrusted(prompt: true)
    }
}
