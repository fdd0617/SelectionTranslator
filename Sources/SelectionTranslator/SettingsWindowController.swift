import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(keychain: KeychainStore) {
        let rootView = SettingsView(keychain: keychain)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
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

    @State private var apiURL: String = UserDefaults.standard.string(forKey: SettingsKeys.apiURL) ?? OpenAITranslator.defaultAPIURL
    @State private var apiKey: String = ""
    @State private var model: String = UserDefaults.standard.string(forKey: SettingsKeys.model) ?? OpenAITranslator.defaultModel
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
                    Text("配置兼容 OpenAI 的中转站、模型和系统权限")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingsField(title: "API URL / Base URL", subtitle: "可填写 /v1，保存时会自动补全 /chat/completions") {
                    TextField("https://api.openai.com/v1", text: $apiURL)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsField(title: "API Key", subtitle: "保存到 macOS Keychain") {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsField(title: "Model", subtitle: "填写中转站支持的模型名") {
                    TextField("gpt-4.1-mini", text: $model)
                        .textFieldStyle(.roundedBorder)
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
        .frame(width: 620, height: 420)
        .background {
            LinearGradient(
                colors: [Color.primary.opacity(0.04), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .onAppear {
            apiKey = keychain.readAPIKey() ?? ""
        }
    }

    private func save() {
        do {
            let trimmedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard validate(apiURL: trimmedAPIURL, model: trimmedModel) else { return }

            try keychain.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            UserDefaults.standard.set(normalizedAPIURL(trimmedAPIURL), forKey: SettingsKeys.apiURL)
            UserDefaults.standard.set(trimmedModel, forKey: SettingsKeys.model)
            status = "已保存"
        } catch {
            status = error.localizedDescription
        }
    }

    private var isSuccessStatus: Bool {
        status == "已保存" || status == "连接测试成功"
    }

    private func testConnection() {
        let trimmedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard validate(apiURL: trimmedAPIURL, model: trimmedModel) else { return }
        guard !trimmedAPIKey.isEmpty else {
            status = "API Key 不能为空"
            return
        }

        isTestingConnection = true
        status = "正在测试连接..."

        Task { @MainActor in
            do {
                let translator = OpenAITranslator()
                _ = try await translator.translateToChinese(
                    "Hello, this is a connection test.",
                    apiURL: normalizedAPIURL(trimmedAPIURL),
                    apiKey: trimmedAPIKey,
                    model: trimmedModel
                )
                status = "连接测试成功"
            } catch {
                status = "连接测试失败：\(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }

    private func validate(apiURL: String, model: String) -> Bool {
        guard URL(string: apiURL)?.host != nil else {
            status = "API URL 无效"
            return false
        }
        guard !model.isEmpty else {
            status = "Model 不能为空"
            return false
        }
        return true
    }

    private func normalizedAPIURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else {
            return value
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        }

        return components.string ?? value
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
