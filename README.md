# EasyEQ · 简易均衡器

[中文](#中文) · [English](#english)

---

## 中文

### 简介

简易均衡器（EasyEQ）是一款免费、开源的 macOS 原生系统级均衡器，使用 SwiftUI 构建。它作用于整个系统的声音输出，无需安装任何虚拟声卡或驱动。

<!-- screenshot: docs/screenshot.png -->

- 内置预设：人声、人声·强、原声，也可以保存自己的预设
- 10 / 15 / 31 段可选，直接拖动滑块调节
- 界面语言跟随系统（中文系统显示中文，其他显示英文），也可在设置中更改

### 系统要求

- macOS 14.4 或更高版本

### 安装

1. 在本仓库的 Releases 页面下载最新的 `EasyEQ-<版本>.dmg`（或 `.zip`），将 `EasyEQ.app` 拖入“应用程序”。
2. 目前应用尚未经过 Apple 公证（仅做了临时签名）。首次打开时，如果系统提示无法验证开发者，请打开“系统设置 → 隐私与安全性”，在页面下方点击“仍要打开”（macOS 15 及以上需要这样操作）。
3. 首次启动会请求“系统音频录制”权限：在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中，将 EasyEQ 加入“仅系统音频录制”列表并允许。EasyEQ 只用这个权限处理要播放的声音，不会录音，也不会上传任何内容。
4. 更新应用之后，系统可能要求重新授予该权限。

### 使用

- 在左侧边栏选择预设：人声 / 人声·强 / 原声，或你自己保存的预设。
- 拖动滑块调节各频段；双击某个滑块可将其归零。
- 可切换 10 / 15 / 31 段。用户预设会记住自己的段数。
- 关闭窗口后均衡效果仍然保留；按 ⌘Q 退出应用才会停止效果。
- 听不到效果？窗口底部出现“没效果？检查权限”链接时，点击它检查上述音频权限。

### 从源码构建

需要 Swift 6.0 或更高版本（Xcode 16 及以上）。

```sh
swift test            # 运行测试
scripts/bundle.sh     # 生成 dist/EasyEQ.app（通用二进制，临时签名）
scripts/package.sh 0.1.0   # 生成 dist/EasyEQ-0.1.0.zip 和 .dmg
```

设置环境变量 `SIGN_IDENTITY` 可使用你自己的签名证书代替临时签名。

### 卸载

1. 退出 EasyEQ，将 `EasyEQ.app` 移到废纸篓。
2. 删除用户数据：`~/Library/Application Support/EasyEQ`
3. 清除设置：`defaults delete app.easyeq.EasyEQ`

### 许可证

[MIT](LICENSE)

---

## English

### What it is

EasyEQ is a free, open-source, native macOS system-wide equalizer built with SwiftUI. It processes all of your Mac's audio output, with no virtual audio device or driver to install.

<!-- screenshot: docs/screenshot.png -->

- Built-in presets: Voice, Voice+, Flat. You can also save your own.
- 10, 15 or 31 bands; just drag the sliders.
- The interface language follows the system (Chinese on Chinese systems, English otherwise) and can be changed in Settings.

### Requirements

- macOS 14.4 or later

### Install

1. Download the latest `EasyEQ-<version>.dmg` (or `.zip`) from the Releases page of this repository and drag `EasyEQ.app` into Applications.
2. The app is not notarized yet (it is ad-hoc signed only). On first launch, if macOS says it cannot verify the developer, open System Settings → Privacy & Security and click "Open Anyway" near the bottom (required on macOS 15 and later).
3. On first launch EasyEQ asks for the System Audio Recording permission. Under System Settings → Privacy & Security → Screen & System Audio Recording, add EasyEQ to the "System Audio Recording Only" list and allow it. EasyEQ only uses it to process the sound being played; nothing is recorded or sent anywhere.
4. After updating the app, macOS may ask you to grant the permission again.

### Usage

- Pick a preset in the left sidebar: Voice / Voice+ / Flat, or one you saved.
- Drag a slider to adjust its band; double-click a slider to reset it to 0.
- Switch between 10, 15 and 31 bands. Each user preset remembers its own band count.
- Closing the window keeps the effect running; press ⌘Q to quit and stop it.
- No effect? If the "No effect? Check permission" link appears in the window footer, click it to review the audio permission above.

### Build from source

Requires Swift 6.0 or later (Xcode 16+).

```sh
swift test            # run the tests
scripts/bundle.sh     # build dist/EasyEQ.app (universal binary, ad-hoc signed)
scripts/package.sh 0.1.0   # build dist/EasyEQ-0.1.0.zip and .dmg
```

Set the `SIGN_IDENTITY` environment variable to sign with your own certificate instead of ad-hoc.

### Uninstall

1. Quit EasyEQ and move `EasyEQ.app` to the Trash.
2. Delete user data: `~/Library/Application Support/EasyEQ`
3. Clear settings: `defaults delete app.easyeq.EasyEQ`

### License

[MIT](LICENSE)
