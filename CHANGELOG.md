# Changelog · 更新日志

All notable changes to EasyEQ. Downloads: [Releases](https://github.com/gzldc/EasyEQ/releases).
EasyEQ 每个版本的主要改动。下载见 [Releases](https://github.com/gzldc/EasyEQ/releases)。

## [0.2.0] — 2026-10-22

### English

**New**
- **10 built-in presets** (was 3): Voice, Voice+, Podcast, Movie, Music, Night, Less Bass, Bass Boost, Treble Boost, Flat — each with a one-line description.
- **Preset groups** — create, rename and delete collapsible groups; drag a preset onto a group or use *Move to Group*. Deleting a group keeps its presets. Collapsed state is remembered, and *Built-in* can be collapsed too.
- **Import / export presets** as `.json` files (multi-file import, automatic renaming of duplicates, broken files reported individually).
- **Paint-style editing** for dense layouts — drag sideways across the sliders to paint the curve; hover readout (`1.25K · +3.0 dB`), scroll-wheel nudging (0.5 dB/step), half-labelled 31-band axis.
- **Smooth** and **Reset All** buttons.
- **Keyboard shortcuts** — ⌘N new preset, ⌘S save, ⇧⌘S save as, ⌘E toggle the effect.
- **Launch at Login** switch in Settings (offered once the app is in Applications).
- **Delete confirmation** for presets.
- **New app icon** and a **styled drag-to-install DMG** window.
- **Repair System Audio** — when macOS's audio service (`coreaudiod`) stops responding, the footer offers a one-click repair through the system's administrator dialog, then reconnects automatically.

**Improved**
- All Core Audio work runs on a background queue with a watchdog — no more UI stall on launch or device changes, and a stuck audio service can't freeze the app.
- When the output device's driver drops out, EasyEQ tears down at once (original sound first) and rebuilds when the device returns. Unrelated device changes no longer cause a rebuild.
- Bundle versioning: `CFBundleShortVersionString` is always numeric; the full version goes into `CFBundleVersion`.
- Test builds for any branch via GitHub Actions; `-` tags become pre-releases.

**Fixed**
- A paint drag stays on its starting column until it moves past half a column.
- Smooth snaps values within 0.3 dB of flat to zero.
- An unreadable `groups.json` is moved aside instead of being overwritten.
- Menu shortcuts are disabled while a confirmation or error alert is showing.
- Malformed optional preset fields are tolerated on load.

### 中文

**新增**
- **10 个内置预设**（原来 3 个）：人声、人声·强、播客、电影、音乐、夜间、低音减弱、低音增强、高音增强、原声，每个都有一句说明。
- **预设分组**：新建、重命名、删除可折叠的分组；把预设拖到分组上或用“移到分组”。删除分组不会删除预设。折叠状态会记住，“内置”也能折叠。
- **导入 / 导出预设**为 `.json` 文件（可一次导入多个，重名自动改名，坏文件单独提示）。
- **画笔式编辑**：在滑块上横向划过即可画出曲线；悬停显示读数（`1.25K · +3.0 dB`）、滚轮每格 0.5 dB 微调、31 段频率标签隔一个显示。
- **平滑**、**归零**按钮。
- **快捷键**：⌘N 新建预设、⌘S 保存、⇧⌘S 另存为、⌘E 打开 / 关闭效果。
- 设置里新增**开机自动启动**（App 放进“应用程序”后可用）。
- 删除预设前**二次确认**。
- **新 App 图标**和**带引导的拖拽安装 DMG 窗口**。
- **修复系统声音**：macOS 音频服务（`coreaudiod`）无响应时，底部提供一键修复（通过系统管理员授权框），修复后自动重新接上。

**改进**
- 所有 Core Audio 操作移到后台队列并带看门狗：启动、切换设备时界面不再卡顿，系统音频服务卡死也不会拖死界面。
- 输出设备驱动掉线时立即拆除（先恢复原声），设备回来后自动重建；与当前输出无关的设备变化不再触发重建。
- 版本号：`CFBundleShortVersionString` 始终是纯数字，完整版本写入 `CFBundleVersion`。
- GitHub Actions 可为任意分支生成测试包；带 `-` 的标签发布为预发布。

**修复**
- 画笔拖动在移过半列之前只改起始那一列。
- “平滑”后离 0 不到 0.3 dB 的值归零。
- `groups.json` 损坏时先另存备份，不再被覆盖。
- 确认框或错误提示弹出时，菜单快捷键暂时停用。
- 预设文件里格式不对的可选字段不再导致读取失败。

## [0.1.0] — 2026-10-22

First public release · 首个公开版本

- System-wide EQ with no driver (Core Audio Process Tap) · 无需驱动的系统级均衡（Core Audio Process Tap）
- 10 / 15 / 31 bands with plain-language names · 10 / 15 / 31 段，频段大白话命名
- Built-in Voice, Voice+, Flat; your own presets (new, save, save as, rename, delete) · 内置人声、人声·强、原声；自定义预设（新建、保存、另存为、重命名、删除）
- Live response curve, headroom + limiter, click-free ramps · 实时曲线、自动余量 + 限幅、无爆音过渡
- Follows the default output device; keeps running when the window is closed · 跟随默认输出设备；关窗口后继续生效
- Light / dark glass UI, English / Chinese · 浅色 / 深色玻璃风格界面，中英双语

[0.2.0]: https://github.com/gzldc/EasyEQ/releases/tag/v0.2.0
[0.1.0]: https://github.com/gzldc/EasyEQ/releases/tag/v0.1.0
