import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var autoCloseTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var wasClickedAfterShowing = false

    func showLoading(message: String) {
        show(content: .loading(message))
    }

    func showTranslation(translation: String, original: String, onRetry: @escaping () -> Void) {
        show(content: .translation(translation: translation, original: original, onRetry: onRetry))
    }

    func showError(message: String, detail: String?, actionTitle: String?, action: (() -> Void)?) {
        show(content: .error(message: message, detail: detail, actionTitle: actionTitle, action: action))
    }

    private func show(content: PanelContent) {
        let panel = makePanel()
        let rootView = TranslationPanelView(
            content: content,
            onClose: { [weak self] in self?.close() },
            onCopy: { value in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        )

        panel.contentView = NSHostingView(rootView: rootView)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleAutoCloseIfNotClicked()
    }

    private func makePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false

        return panel
    }

    private func position(_ panel: NSPanel) {
        let size = NSSize(width: 460, height: 300)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width - 12
        }
        if origin.y < visibleFrame.minY {
            origin.y = mouse.y + 16
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = visibleFrame.maxY - size.height - 12
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + 12
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func close() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        removeClickMonitor()
        panel?.orderOut(nil)
    }

    private func scheduleAutoCloseIfNotClicked() {
        autoCloseTask?.cancel()
        removeClickMonitor()
        wasClickedAfterShowing = false

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalClick(event)
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleLocalClick(event)
            }
            return event
        }

        autoCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled, !wasClickedAfterShowing {
                close()
            }
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        if panel.frame.contains(event.locationInWindow) {
            cancelAutoCloseAfterClick()
        }
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard let panel, panel.isVisible, event.window === panel else { return }
        cancelAutoCloseAfterClick()
    }

    private func cancelAutoCloseAfterClick() {
        wasClickedAfterShowing = true
        autoCloseTask?.cancel()
        autoCloseTask = nil
        removeClickMonitor()
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }
}

enum PanelContent {
    case loading(String)
    case translation(translation: String, original: String, onRetry: () -> Void)
    case error(message: String, detail: String?, actionTitle: String?, action: (() -> Void)?)
}

struct TranslationPanelView: View {
    let content: PanelContent
    let onClose: () -> Void
    let onCopy: (String) -> Void

    @State private var showsOriginal = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Group {
                switch content {
                case .loading(let message):
                    loadingView(message)
                case .translation(let translation, let original, let onRetry):
                    translationView(translation: translation, original: original, onRetry: onRetry)
                case .error(let message, let detail, let actionTitle, let action):
                    errorView(message: message, detail: detail, actionTitle: actionTitle, action: action)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(width: 460, height: 300)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.accentColor.opacity(0.07),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.24), radius: 28, y: 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: headerIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭")
        }
    }

    private var headerTitle: String {
        switch content {
        case .loading:
            return "正在翻译"
        case .translation:
            return "翻译结果"
        case .error:
            return "翻译失败"
        }
    }

    private var headerSubtitle: String {
        switch content {
        case .loading:
            return "读取选区并请求翻译服务"
        case .translation:
            return "3 秒内未点击会自动收起"
        case .error:
            return "检查配置、网络或模型名称"
        }
    }

    private var headerIconName: String {
        switch content {
        case .loading:
            return "sparkles"
        case .translation:
            return "character.book.closed"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
        }
    }

    private func translationView(translation: String, original: String, onRetry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(translation)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsOriginal {
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                            Text("原文")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(original)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .lineSpacing(3)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    onCopy(translation)
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(PanelActionButtonStyle(isProminent: true))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsOriginal.toggle()
                    }
                } label: {
                    Label(showsOriginal ? "隐藏原文" : "原文", systemImage: showsOriginal ? "eye.slash" : "text.quote")
                }
                .buttonStyle(PanelActionButtonStyle())

                Spacer()

                Button(action: onRetry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PanelActionButtonStyle())
            }
        }
    }

    private func errorView(message: String, detail: String?, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let detail, !detail.isEmpty {
                    ScrollView {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                if let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: "arrow.right")
                    }
                    .buttonStyle(PanelActionButtonStyle(isProminent: true))
                }
            }
        }
    }
}

struct PanelActionButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isProminent ? Color.accentColor : Color.primary.opacity(0.075))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
