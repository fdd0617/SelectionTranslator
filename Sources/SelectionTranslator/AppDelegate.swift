import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keychain = KeychainStore()
    private let selectionReader = SelectionReader()
    private let openAITranslator = OpenAITranslator()
    private let anthropicTranslator = AnthropicTranslator()
    private let deepLXTranslator = DeepLXTranslator()
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

    private func translateSelection(isAutomatic: Bool = false, textToTranslate: String? = nil) {
        if isAutomatic, textToTranslate == nil, !UserDefaults.standard.bool(forKey: SettingsKeys.automaticTranslationEnabled) {
            return
        }

        translationTask?.cancel()
        requestCounter += 1
        let requestID = requestCounter

        translationTask = Task { @MainActor in
            if textToTranslate == nil {
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
            }

            let provider = TranslationProvider.savedValue()

            let apiKey = keychain.readAPIKey(for: provider) ?? ""
            guard !provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if isAutomatic { return }
                panelController.showError(
                    message: "请先配置 API Key",
                    detail: nil,
                    actionTitle: "打开设置",
                    action: { [weak self] in self?.showSettings() }
                )
                return
            }

            var retryText = textToTranslate

            do {
                let selectedText: String
                if let textToTranslate {
                    selectedText = textToTranslate
                } else {
                    selectedText = try await selectionReader.readSelectedText()
                    retryText = selectedText
                }
                try Task.checkCancellation()

                guard SelectionContentFilter.shouldTranslate(selectedText) else {
                    return
                }

                let apiURL = savedAPIURL(for: provider)
                let model = savedModel(for: provider)
                let cacheKey = TranslationCache.key(text: selectedText, provider: provider, apiURL: apiURL, model: model)

                if let cachedText = await TranslationCache.shared.value(for: cacheKey), isCurrentRequest(requestID) {
                    panelController.showTranslation(
                        translation: cachedText,
                        original: selectedText,
                        onRetry: { [weak self] in self?.translateSelection(textToTranslate: selectedText) }
                    )
                    return
                }

                panelController.showLoading(message: "正在翻译...")

                let translatedText: String
                switch provider {
                case .openAICompatible:
                    translatedText = try await openAITranslator.translateToChinese(
                        selectedText,
                        apiURL: apiURL,
                        apiKey: apiKey,
                        model: model
                    )
                case .anthropicNative:
                    translatedText = try await anthropicTranslator.translateToChinese(
                        selectedText,
                        apiURL: apiURL,
                        apiKey: apiKey,
                        model: model
                    )
                case .deepLX:
                    translatedText = try await deepLXTranslator.translateToChinese(
                        selectedText,
                        apiURL: apiURL,
                        apiKey: apiKey
                    )
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID) else { return }

                await TranslationCache.shared.store(translatedText, for: cacheKey)

                panelController.showTranslation(
                    translation: translatedText,
                    original: selectedText,
                    onRetry: { [weak self] in self?.translateSelection(textToTranslate: selectedText) }
                )
            } catch {
                if error is CancellationError {
                    return
                }

                if case SelectionReaderError.noSelectedText = error {
                    return
                }

                guard isCurrentRequest(requestID) else { return }

                let retryAction: () -> Void
                if let retryText {
                    retryAction = { [weak self] in self?.translateSelection(textToTranslate: retryText) }
                } else {
                    retryAction = { [weak self] in self?.translateSelection() }
                }

                panelController.showError(
                    message: "翻译失败",
                    detail: error.localizedDescription,
                    actionTitle: "重试",
                    action: retryAction
                )
            }
        }
    }

    private func isCurrentRequest(_ requestID: Int) -> Bool {
        requestID == requestCounter && translationTask?.isCancelled == false
    }

    private func savedAPIURL(for provider: TranslationProvider) -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.apiURL(for: provider))
            ?? legacySavedValue(for: provider, key: SettingsKeys.apiURL)
            ?? provider.defaultAPIURL
    }

    private func savedModel(for provider: TranslationProvider) -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.model(for: provider))
            ?? legacySavedValue(for: provider, key: SettingsKeys.model)
            ?? provider.defaultModel
    }

    private func legacySavedValue(for provider: TranslationProvider, key: String) -> String? {
        guard TranslationProvider.savedValue() == provider else {
            return nil
        }
        return UserDefaults.standard.string(forKey: key)
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    private func requestAccessibilityPermission() {
        _ = selectionReader.isAccessibilityTrusted(prompt: true)
    }
}
