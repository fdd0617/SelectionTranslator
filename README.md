# Selection Translator

macOS 全局划词翻译 MVP。按住鼠标左键拖选文本并松开后，应用会临时执行复制、恢复原剪贴板、调用翻译 API，并在鼠标附近显示中文浮窗。也可以按 `⌥ Space` 手动翻译当前选区。

## 功能

- 菜单栏常驻入口
- 鼠标左键拖选后自动翻译
- `⌥ Space` 全局快捷键
- 临时读取选区并恢复原剪贴板
- 默认忽略空白、纯中文、纯数字和网址选区
- 兼容 OpenAI Chat Completions 的 API 翻译为简体中文，可配置中转站 URL
- API Key 保存到 macOS Keychain
- 鼠标附近浮窗显示译文，可展开原文、复制译文、重试
- 浮窗错误提示：未配置 API Key、未授权辅助功能、未检测到选区、请求失败
- 设置页支持 API URL、API Key、模型配置和连接测试

## 本地运行

```bash
swift run SelectionTranslator
```

如果本机 `swift build` 报出 Swift 编译器和 macOS SDK 版本不匹配，需要安装匹配版本的 Xcode/Command Line Tools，或用 `xcode-select` 切到可用的 Xcode。

首次运行后，在菜单栏打开 `设置...`：

1. 填入 API URL。默认是 `https://api.openai.com/v1/chat/completions`。使用中转站时可以填 base URL，例如 `https://your-api.example.com/v1`，应用会自动补成 `/chat/completions`。
2. 填入 API Key。
3. 保留默认模型 `gpt-4.1-mini`，或改成你的可用模型。
4. 点击保存。
5. 点击 `检查辅助功能权限`，在系统设置里允许本工具控制电脑。

之后在任意 App 中按住鼠标左键拖选可复制的英文文本，松开后会自动翻译。也可以选中文本后按 `⌥ Space` 手动翻译。

## 打包成 `.app`

先确保本机 Xcode/Command Line Tools 的 Swift 编译器和 macOS SDK 版本匹配。然后运行：

```bash
./scripts/package-app.sh
```

脚本会执行 release 构建，并生成：

```text
dist/SelectionTranslator.app
```

打开应用：

```bash
open dist/SelectionTranslator.app
```

首次打开后，在菜单栏进入 `设置...` 配置 API URL、API Key 和模型，并在系统设置里给 `SelectionTranslator.app` 授权辅助功能权限。

如果要自定义 bundle id 或版本号：

```bash
BUNDLE_ID=com.example.SelectionTranslator VERSION=1.0.0 BUILD=1 ./scripts/package-app.sh
```

## 项目结构

```text
Package.swift                         SwiftPM 可执行应用配置
Sources/SelectionTranslator/          应用源码
scripts/package-app.sh                本地打包 .app 脚本
README.md                             使用说明
.gitignore                            Git 忽略规则
```

上传 GitHub 时建议提交源码、脚本和文档；不要提交 `.build/`、`dist/`、`work/`、`outputs/`、`.DS_Store` 等本地构建产物和临时文件。

## 实现说明

- 技术栈：Swift + SwiftUI + AppKit。
- 选区读取：模拟 `Cmd+C`，读取剪贴板，再恢复原剪贴板内容。
- 翻译引擎：兼容 OpenAI Chat Completions 的 API。
- 翻译策略：保留代码、命令、路径、变量名、错误码、产品名和 URL，翻译自然语言说明。
- 浮窗规则：弹出后 3 秒内未点击会自动关闭；点击浮窗后保持显示；`Esc` 可关闭；再次拖选或手动翻译会替换当前浮窗。
