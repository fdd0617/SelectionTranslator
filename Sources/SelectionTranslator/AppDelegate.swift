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
    private var translationTask: Task<Void, Never>?
    private var requestCounter = 0

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
        translationTask?.cancel()
        requestCounter += 1
        let requestID = requestCounter

        translationTask = Task { @MainActor in
            guard selectionReader.isAccessibilityTrusted(prompt: !isAutomatic) else {
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
                try Task.checkCancellation()

                guard SelectionContentFilter.shouldTranslate(selectedText) else {
                    return
                }

                let apiURL = UserDefaults.standard.string(forKey: SettingsKeys.apiURL) ?? OpenAITranslator.defaultAPIURL
                let model = UserDefaults.standard.string(forKey: SettingsKeys.model) ?? OpenAITranslator.defaultModel
                let cacheKey = TranslationCache.key(text: selectedText, apiURL: apiURL, model: model)

                if let cachedText = await TranslationCache.shared.value(for: cacheKey), isCurrentRequest(requestID) {
                    panelController.showTranslation(
                        translation: cachedText,
                        original: selectedText,
                        onRetry: { [weak self] in self?.translateSelection() }
                    )
                    return
                }

                panelController.showLoading(message: "正在翻译...")

                let translatedText = try await translator.translateToChinese(
                    selectedText,
                    apiURL: apiURL,
                    apiKey: apiKey,
                    model: model
                )
                try Task.checkCancellation()
                guard isCurrentRequest(requestID) else { return }

                await TranslationCache.shared.store(translatedText, for: cacheKey)

                panelController.showTranslation(
                    translation: translatedText,
                    original: selectedText,
                    onRetry: { [weak self] in self?.translateSelection() }
                )
            } catch {
                if error is CancellationError {
                    return
                }

                if case SelectionReaderError.noSelectedText = error {
                    return
                }

                guard isCurrentRequest(requestID) else { return }

                panelController.showError(
                    message: "翻译失败",
                    detail: error.localizedDescription,
                    actionTitle: "重试",
                    action: { [weak self] in self?.translateSelection() }
                )
            }
        }
    }

    private func isCurrentRequest(_ requestID: Int) -> Bool {
        requestID == requestCounter && translationTask?.isCancelled == false
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    private func requestAccessibilityPermission() {
        _ = selectionReader.isAccessibilityTrusted(prompt: true)
    }
}
