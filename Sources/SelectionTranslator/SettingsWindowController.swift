import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(keychain: KeychainStore) {
        let rootView = SettingsView(keychain: keychain)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Selection Translator 设置"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct SettingsView: View {
    let keychain: KeychainStore
    private let modelCatalog = ModelCatalog()

    @State private var provider: TranslationProvider = TranslationProvider.savedValue()
    @State private var apiURL: String = SettingsView.savedAPIURL(for: TranslationProvider.savedValue())
    @State private var apiKey: String = ""
    @State private var model: String = SettingsView.savedModel(for: TranslationProvider.savedValue())
    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels = false
    @State private var modelFetchCounter = 0
    @State private var automaticTranslationEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsKeys.automaticTranslationEnabled)
    @State private var status: String = ""
    @State private var isTestingConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Selection Translator")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("选择当前使用的翻译服务，并保留各服务配置")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingsField(title: "当前翻译服务", subtitle: "只使用当前选中的服务；其他配置会保留") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $provider) {
                            ForEach(TranslationProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: provider) { newProvider in
                            loadSettings(for: newProvider)
                        }

                        Text("切换服务会加载该服务上次保存的 URL、Key 和模型，不会启用多个服务同时翻译。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsField(title: "API URL / Base URL", subtitle: providerURLSubtitle) {
                    TextField(provider.defaultAPIURL, text: $apiURL)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsField(title: "API Key", subtitle: providerAPIKeySubtitle) {
                    SecureField(providerAPIKeyPlaceholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if provider.supportsModelSelection {
                    SettingsField(title: "Model", subtitle: providerModelSubtitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                if availableModels.isEmpty {
                                    TextField(provider.defaultModel, text: $model)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    Picker("", selection: $model) {
                                        ForEach(availableModels) { model in
                                            Text(model.displayName).tag(model.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }

                                Button {
                                    fetchModels()
                                } label: {
                                    Label(isFetchingModels ? "获取中" : "获取模型", systemImage: isFetchingModels ? "hourglass" : "arrow.clockwise")
                                }
                                .buttonStyle(SettingsSecondaryButtonStyle())
                                .disabled(isFetchingModels)
                            }

                            if availableModels.isEmpty {
                                Text("如果服务不支持模型列表，可以手动输入模型名。")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SettingsField(title: "自动划词翻译", subtitle: "默认关闭，开启后拖选文本会发送到配置的 API") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("拖选文本后自动翻译", isOn: $automaticTranslationEnabled)
                            .toggleStyle(.switch)
                        Text("建议只在信任当前应用和 API 服务时开启；手动翻译快捷键 ⌥ Space 不受此开关影响。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button {
                    save()
                } label: {
                    Label("保存配置", systemImage: "checkmark")
                }
                .buttonStyle(SettingsPrimaryButtonStyle())

                Button {
                    let reader = SelectionReader()
                    _ = reader.isAccessibilityTrusted(prompt: true)
                } label: {
                    Label("检查辅助功能权限", systemImage: "lock.shield")
                }
                .buttonStyle(SettingsSecondaryButtonStyle())

                Button {
                    testConnection()
                } label: {
                    Label(isTestingConnection ? "测试中" : "测试连接", systemImage: isTestingConnection ? "hourglass" : "network")
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(isTestingConnection)

                Spacer()
            }

            if !status.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: status == "已保存" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(status)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isSuccessStatus ? Color.green : Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 660, height: 560)
        .background {
            LinearGradient(
                colors: [Color.primary.opacity(0.04), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .onAppear {
            loadSettings(for: provider)
        }
    }

    private func save() {
        do {
            let trimmedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = provider.supportsModelSelection ? model.trimmingCharacters(in: .whitespacesAndNewlines) : provider.defaultModel
            guard let normalizedAPIURL = validatedAPIURLString(apiURL: trimmedAPIURL, model: trimmedModel) else { return }

            try keychain.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
            UserDefaults.standard.set(normalizedAPIURL, forKey: SettingsKeys.apiURL(for: provider))
            UserDefaults.standard.set(trimmedModel, forKey: SettingsKeys.model(for: provider))
            UserDefaults.standard.set(provider.rawValue, forKey: SettingsKeys.provider)
            UserDefaults.standard.set(automaticTranslationEnabled, forKey: SettingsKeys.automaticTranslationEnabled)
            status = "已保存"
        } catch {
            status = error.localizedDescription
        }
    }

    private var isSuccessStatus: Bool {
        status == "已保存" || status == "连接测试成功" || status.hasPrefix("已获取")
    }

    private func testConnection() {
        let providerToTest = provider
        let trimmedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = providerToTest.supportsModelSelection ? model.trimmingCharacters(in: .whitespacesAndNewlines) : providerToTest.defaultModel

        guard let normalizedAPIURL = validatedAPIURLString(apiURL: trimmedAPIURL, model: trimmedModel) else { return }
        guard !providerToTest.requiresAPIKey || !trimmedAPIKey.isEmpty else {
            status = "API Key 不能为空"
            return
        }

        isTestingConnection = true
        status = "正在测试连接..."

        Task { @MainActor in
            do {
                switch providerToTest {
                case .openAICompatible:
                    let translator = OpenAITranslator()
                    _ = try await translator.translateToChinese(
                        "Hello, this is a connection test.",
                        apiURL: normalizedAPIURL,
                        apiKey: trimmedAPIKey,
                        model: trimmedModel
                    )
                case .anthropicNative:
                    let translator = AnthropicTranslator()
                    _ = try await translator.translateToChinese(
                        "Hello, this is a connection test.",
                        apiURL: normalizedAPIURL,
                        apiKey: trimmedAPIKey,
                        model: trimmedModel
                    )
                case .deepLX:
                    let translator = DeepLXTranslator()
                    _ = try await translator.translateToChinese(
                        "Hello, this is a connection test.",
                        apiURL: normalizedAPIURL,
                        apiKey: trimmedAPIKey
                    )
                }
                status = "连接测试成功"
            } catch {
                status = "连接测试失败：\(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }

    private func validatedAPIURLString(apiURL: String, model: String) -> String? {
        guard provider.supportsModelSelection == false || !model.isEmpty else {
            status = "Model 不能为空"
            return nil
        }

        do {
            switch provider {
            case .openAICompatible:
                return try APIEndpointValidator.normalizedChatCompletionsURLString(from: apiURL)
            case .anthropicNative:
                return try AnthropicTranslator.normalizedMessagesURLString(from: apiURL)
            case .deepLX:
                return try DeepLXTranslator.normalizedTranslateURLString(from: apiURL)
            }
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    private var providerURLSubtitle: String {
        switch provider {
        case .openAICompatible:
            return "可填写 /v1，保存时会自动补全 /chat/completions"
        case .anthropicNative:
            return "可填写 /v1，保存时会自动补全 /messages"
        case .deepLX:
            return "可填写 DeepLX base URL，保存时会自动补全 /translate"
        }
    }

    private var providerAPIKeySubtitle: String {
        switch provider {
        case .openAICompatible, .anthropicNative:
            return "保存到 macOS Keychain"
        case .deepLX:
            return "可选；自建 DeepLX 如果启用 token 才需要填写"
        }
    }

    private var providerAPIKeyPlaceholder: String {
        switch provider {
        case .openAICompatible:
            return "sk-..."
        case .anthropicNative:
            return "sk-ant-..."
        case .deepLX:
            return "可留空"
        }
    }

    private var providerModelSubtitle: String {
        switch provider {
        case .openAICompatible:
            return "填写中转站支持的 OpenAI 兼容模型名"
        case .anthropicNative:
            return "填写 Anthropic 原生模型 ID"
        case .deepLX:
            return "DeepLX 不需要模型"
        }
    }

    private func loadSettings(for provider: TranslationProvider) {
        modelFetchCounter += 1
        isFetchingModels = false
        apiURL = Self.savedAPIURL(for: provider)
        model = Self.savedModel(for: provider)
        apiKey = keychain.readAPIKey(for: provider) ?? ""
        availableModels = []
        status = ""
        fetchModelsIfPossible()
    }

    private static func savedAPIURL(for provider: TranslationProvider) -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.apiURL(for: provider))
            ?? legacySavedValue(for: provider, key: SettingsKeys.apiURL)
            ?? provider.defaultAPIURL
    }

    private static func savedModel(for provider: TranslationProvider) -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.model(for: provider))
            ?? legacySavedValue(for: provider, key: SettingsKeys.model)
            ?? provider.defaultModel
    }

    private static func legacySavedValue(for provider: TranslationProvider, key: String) -> String? {
        guard TranslationProvider.savedValue() == provider else {
            return nil
        }
        return UserDefaults.standard.string(forKey: key)
    }

    private func fetchModelsIfPossible() {
        guard provider.supportsModelSelection,
              !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        fetchModels()
    }

    private func fetchModels() {
        modelFetchCounter += 1
        let fetchID = modelFetchCounter
        let providerToFetch = provider
        let apiURLToFetch = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKeyToFetch = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard providerToFetch.supportsModelSelection else {
            status = "\(providerToFetch.displayName) 不需要模型列表"
            return
        }
        guard !apiURLToFetch.isEmpty else {
            status = "API URL 不能为空"
            return
        }
        guard !apiKeyToFetch.isEmpty else {
            status = "API Key 不能为空"
            return
        }

        isFetchingModels = true
        status = "正在获取模型列表..."

        Task { @MainActor in
            do {
                let models = try await modelCatalog.fetchModels(
                    provider: providerToFetch,
                    apiURL: apiURLToFetch,
                    apiKey: apiKeyToFetch
                )

                guard fetchID == modelFetchCounter, provider == providerToFetch else {
                    return
                }

                availableModels = models
                if !models.contains(where: { $0.id == model }), let firstModel = models.first {
                    model = firstModel.id
                }
                status = "已获取 \(models.count) 个模型"
            } catch {
                guard fetchID == modelFetchCounter, provider == providerToFetch else {
                    return
                }
                availableModels = []
                status = "获取模型失败：\(error.localizedDescription)"
            }
            if fetchID == modelFetchCounter {
                isFetchingModels = false
            }
        }
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.primary)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
