<div align="center">

# EasyEQ · 简易均衡器

**一个简单、好看、完全免费的 Mac 系统级均衡器。**<br>
**A simple, good-looking, completely free system-wide equalizer for Mac.**

![macOS 14.4+](https://img.shields.io/badge/macOS-14.4%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![No driver](https://img.shields.io/badge/driver-none%20needed-brightgreen)

[中文](#中文) · [English](#english) · [下载 Download](https://github.com/gzldc/EasyEQ/releases/latest)

<img src="docs/images/screenshot-light.jpg" alt="EasyEQ 浅色界面 / light appearance" width="49%"> <img src="docs/images/screenshot-dark.jpg" alt="EasyEQ 深色界面 / dark appearance" width="49%">

</div>

---

## 中文

### 为什么做 EasyEQ

我用 Mac Studio + Studio Display 的扬声器看视频和直播。显示器本身低音偏厚，碰上人声本来就浑的视频，说话声就发闷、听着累。我只想要一个**简单的系统级均衡器**：把低音压一压、咬字提一提，存几个预设随时切换。

试过的软件都不太对：有的要每天倒计时付费，有的要装驱动、还得手动切换输出设备，有的界面只标着“32、64、125……”看不懂。于是就有了 EasyEQ。

### 优势

- **完全免费，没有任何限制**：没有试用期、没有每天 30 分钟倒计时、没有“升级专业版”。开源（MIT）。
- **不装驱动、不改设置**：使用 macOS 自带的系统音频捕获能力（Core Audio Process Tap）。装好、授权一次就能用，**不需要去“声音设置”里切换输出设备**，也不会往系统里塞虚拟声卡。
- **看得懂**：每个滑块都写着大白话——重低音、浑厚、发闷、咬字、清晰、齿音……不懂音频也知道往哪拖。
- **为“听清人声”而生**：内置“人声”“人声·强”预设，专门压掉闷声、提清咬字，看直播、网课、播客一键变清楚。
- **直接拖、实时听**：按住滑块拖动，声音和曲线同时变化；双击滑块归零。不用先双击再进二级面板。
- **存的就是听到的**：保存的预设和你当下听到的一模一样，重启后依然如此。
- **好看、轻量**：清淡的玻璃风格界面，浅色/深色可选；只在你操作的一瞬间有过渡动画，平时完全静止，几乎不占资源。
- **中英双语**：默认跟随系统语言，也可在设置里手动切换。
- **隐私**：不联网、不收集任何数据，权限只用来处理正在播放的声音，不录音。

### 和其他软件对比

| | **EasyEQ** | Sonora | Radioform | eqMac | FineTune | SoundSource |
|---|---|---|---|---|---|---|
| 价格 | **完全免费** | 均衡器免费；额外功能每天限时 30 分钟 | 免费 | 基础免费，高级均衡器需付费 Pro | 免费 | 付费 |
| 开源 | **✅ MIT** | ❌ | ✅ GPL-3.0 | 部分（公开源码停在旧版） | ✅ GPL-3.0 | ❌ |
| 需要安装音频驱动 | **不需要** | 不需要 | 需要 | 需要 | 不需要 | — |
| 需要手动切换输出设备 | **不需要** | 不需要 | 需要 | — | 不需要 | 不需要 |
| 界面形态 | **独立窗口** | 独立窗口 | 菜单栏小面板 | 菜单栏 | 菜单栏 | 菜单栏 |
| 频段 | **10 / 15 / 31 段可选** | 10 / 20 段等 | 10 段（参数） | 3 段 / 10 段（Pro） | 10 段 | 按 App 均衡 |
| 频段大白话名称 | **✅** | — | ❌ | ❌ | ❌ | ❌ |
| 中文界面 | **✅** | ✅ | — | — | — | — |
| 重点 | 简单、听清人声 | 功能全面 | 轻量开源 | 老牌均衡器 | 按 App 调音量 | 专业音频路由 |

> 对比信息整理于 2026 年 10 月，来自各软件官网与代码仓库；“—”表示未核实。如有变化欢迎提 Issue 指正。
> 想按 App 分别调音量，FineTune、SoundSource 更合适；只想让 Mac 的声音整体更顺耳，EasyEQ 最省事。

### 主要功能

- **系统级均衡**：对浏览器、视频网站、播放器等所有正在播放的声音生效。
- **三档频段**：10 段（默认）、15 段、31 段，都是行业标准的图示均衡器频点；切换时按当前曲线自动换算，声音基本不变。
- **内置预设**：人声（看直播、讲课）、人声·强（说话特别闷时）、原声（不做处理）。
- **自己的预设**：新建、保存、另存为、改名、删除；每个预设记住自己的段数。
- **实时曲线**：滑块上方的曲线实时显示整体效果。
- **防爆音**：自动降低整体电平 + 限幅器，所有频段拉满也不会破音；拖动时平滑过渡，没有“咔哒”声。
- **跟随输出设备**：插拔耳机、切换显示器扬声器时自动跟过去。
- **关窗口不停**：关掉窗口效果继续，软件留在 Dock；按 ⌘Q 退出后声音立即恢复原样。
- **外观**：浅色 / 深色 / 跟随系统。
- **语言**：中文 / English / 跟随系统。

<p align="center"><img src="docs/images/screenshot-31-bands.jpg" alt="31 段模式" width="70%"></p>

### 系统要求

- macOS 14.4 或更高版本（Apple 芯片与 Intel 均可）

### 安装

1. 到 [Releases](https://github.com/gzldc/EasyEQ/releases/latest) 下载最新的 `EasyEQ-<版本>.dmg`，打开后把 `EasyEQ.app` 拖进“应用程序”。
2. 目前还没有经过 Apple 公证。第一次打开如果提示“无法验证开发者”：打开“系统设置 → 隐私与安全性”，在页面下方点“仍要打开”（macOS 15 起右键“打开”已不能绕过）。
3. 第一次启动会请求“系统音频录制”权限，点“允许”。也可以在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制 → 仅系统音频录制”里打开 EasyEQ。
4. 升级到新版本后，系统可能会再请求一次权限，这是正常的。

### 使用

1. 左边选一个预设，比如“人声”，声音马上生效。
2. 想微调：按住某个滑块上下拖；双击滑块归零。
3. 调满意了点“保存”（内置预设会让你另存为新预设）。
4. 右上角可以切换 10 / 15 / 31 段，或用开关临时关闭效果对比。
5. 听不到效果？窗口底部出现“没效果？检查权限”时，点它检查上面的音频权限。

### 常见问题

- **为什么需要“系统音频录制”权限？** macOS 规定，处理其他软件播放的声音必须有这个权限。EasyEQ 只在本机实时处理声音，不录音、不保存、不上传。
- **会影响音质或延迟吗？** 处理在本机实时完成，缓冲很小，看视频口型不会错位；选“原声”或关闭开关时声音与不开软件一致。
- **退出后声音正常吗？** 按 ⌘Q 退出后，系统声音立即恢复原样。

### 从源码构建

需要 Swift 6.0 或更高版本（Xcode 16 及以上）。

```sh
swift test                 # 运行测试
scripts/bundle.sh          # 生成 dist/EasyEQ.app（通用二进制）
scripts/package.sh 0.1.0   # 生成 dist/EasyEQ-0.1.0.zip 和 .dmg
```

- 默认使用临时签名（ad-hoc）。设置环境变量 `SIGN_IDENTITY` 可改用你自己的证书。
- 本地开发小技巧：如果钥匙串里有名为 `EasyEQ Local Signing` 的自签名代码签名证书，脚本会自动使用它，这样重新编译后不用反复授权系统音频权限。

### 技术原理

- 用 Core Audio Process Tap 捕获全部系统声音并让原声静音，处理后再输出到当前默认设备，不需要任何驱动。
- 每个频段是一个 RBJ 峰值双二阶滤波器，串联处理；实时线程中不分配内存、不加锁。
- 纯逻辑（频段、换算、预设、编辑、设置、多语言）与音频处理都有自动化测试。

### 卸载

1. 退出 EasyEQ，把 `EasyEQ.app` 移到废纸篓。
2. 删除预设：`~/Library/Application Support/EasyEQ`
3. 清除设置：`defaults delete app.easyeq.EasyEQ`

### 许可证

[MIT](LICENSE)

---

## English

### Why EasyEQ

I watch videos and live streams on a Mac Studio with the Studio Display speakers. The display already leans bass-heavy, so voices that are a bit muddy to begin with end up boomy and tiring. All I wanted was a **simple system-wide equalizer**: pull the bass down, lift the diction, save a few presets and switch between them.

Nothing I tried felt right: one had a daily paid countdown, one needed a driver plus manually switching the output device, and others only labelled bands "32, 64, 125…". So I built EasyEQ.

### Highlights

- **Completely free, no limits** — no trial, no 30-minutes-a-day countdown, no "upgrade to Pro". Open source (MIT).
- **No driver, no settings to change** — uses macOS's built-in system audio capture (Core Audio Process Tap). Grant permission once and it works; **no switching the output device** in Sound settings, no virtual audio device added to your system.
- **Readable** — every slider has a plain-language name: Sub-bass, Warmth, Muddiness, Presence, Clarity, Sibilance… you know where to drag without audio knowledge.
- **Made for clear voices** — built-in Voice and Voice+ presets cut the boom and bring speech forward for streams, classes and podcasts.
- **Drag and hear it live** — press and drag a slider; sound and curve change together. Double-click to reset. No second panel to open.
- **What you save is what you hear** — saved presets sound exactly like what you heard, even after a restart.
- **Good-looking and light** — a soft glass design with light and dark appearances. Animations only play at the moment you act; otherwise the UI is completely still and costs almost nothing.
- **Chinese & English** — follows the system language, switchable in Settings.
- **Private** — no network access, no data collection. The permission is only used to process audio that is playing; nothing is recorded.

### Compared with other apps

| | **EasyEQ** | Sonora | Radioform | eqMac | FineTune | SoundSource |
|---|---|---|---|---|---|---|
| Price | **Free, unlimited** | EQ free; extras limited to 30 min/day | Free | Basic free; advanced EQ needs Pro | Free | Paid |
| Open source | **✅ MIT** | ❌ | ✅ GPL-3.0 | Partly (public source is an old version) | ✅ GPL-3.0 | ❌ |
| Installs an audio driver | **No** | No | Yes | Yes | No | — |
| Must switch output device manually | **No** | No | Yes | — | No | No |
| UI | **Window** | Window | Menu-bar popover | Menu bar | Menu bar | Menu bar |
| Bands | **10 / 15 / 31** | 10 / 20 and more | 10 (parametric) | 3 / 10 (Pro) | 10 | Per-app EQ |
| Plain-language band names | **✅** | — | ❌ | ❌ | ❌ | ❌ |
| Chinese UI | **✅** | ✅ | — | — | — | — |
| Focus | Simple, clear voices | Feature-rich | Lightweight, open | Long-standing EQ | Per-app volume | Pro audio routing |

> Compiled in October 2026 from each app's website and repository; "—" means not verified. Corrections via Issues are welcome.
> If you want per-app volume, FineTune or SoundSource fit better. If you just want your whole Mac to sound easier on the ears, EasyEQ is the simplest.

### Features

- **System-wide EQ** — applies to everything that plays: browsers, video sites, players.
- **Three band layouts** — 10 (default), 15 and 31 bands, all industry-standard graphic-EQ frequencies; switching converts along the current curve so the sound barely changes.
- **Built-in presets** — Voice (streams, lectures), Voice+ (very muddy speech), Flat (no processing).
- **Your own presets** — new, save, save as, rename, delete; each preset remembers its own band count.
- **Live curve** — the curve above the sliders shows the overall response in real time.
- **No clipping** — automatic headroom plus a limiter, so even all bands at max won't distort; smooth ramps mean no clicks while dragging.
- **Follows your output** — plug in headphones or switch speakers and the EQ follows.
- **Keeps running** — closing the window keeps the effect, with the app in the Dock; ⌘Q quits and the sound returns to normal immediately.
- **Appearance** — Light / Dark / Follow System.
- **Language** — 中文 / English / Follow System.

### Requirements

- macOS 14.4 or later (Apple silicon and Intel)

### Install

1. Download the latest `EasyEQ-<version>.dmg` from [Releases](https://github.com/gzldc/EasyEQ/releases/latest), open it and drag `EasyEQ.app` into Applications.
2. The app isn't notarized yet. If macOS says it can't verify the developer on first launch, open System Settings → Privacy & Security and click "Open Anyway" near the bottom (since macOS 15, right-click → Open no longer bypasses this).
3. On first launch EasyEQ asks for the System Audio Recording permission — click Allow. You can also enable it under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only.
4. After updating to a new version, macOS may ask for the permission again. That's expected.

### Usage

1. Pick a preset on the left, e.g. Voice — it applies instantly.
2. To fine-tune, press and drag a slider; double-click a slider to reset it.
3. Happy with it? Click Save (built-in presets ask you to save as a new preset).
4. Switch between 10 / 15 / 31 bands at the top right, or use the switch to compare with the effect off.
5. No effect? If "No effect? Check permission" appears in the footer, click it to check the audio permission.

### FAQ

- **Why the System Audio Recording permission?** macOS requires it to process sound played by other apps. EasyEQ processes audio locally in real time; nothing is recorded, saved or uploaded.
- **Does it add latency or change the sound?** Processing is local with a small buffer, so lip-sync stays right. With Flat or the switch off, it sounds the same as without the app.
- **Is the sound normal after quitting?** Yes — after ⌘Q your system audio returns to normal immediately.

### Build from source

Requires Swift 6.0 or later (Xcode 16+).

```sh
swift test                 # run the tests
scripts/bundle.sh          # build dist/EasyEQ.app (universal binary)
scripts/package.sh 0.1.0   # build dist/EasyEQ-0.1.0.zip and .dmg
```

- Ad-hoc signed by default. Set `SIGN_IDENTITY` to sign with your own certificate.
- Local development tip: if your keychain has a self-signed code-signing identity named `EasyEQ Local Signing`, the scripts use it automatically, so rebuilds don't keep asking for the system-audio permission.

### How it works

- A Core Audio Process Tap captures all system audio and mutes the originals; EasyEQ processes it and plays it on the current default output device — no driver involved.
- Each band is an RBJ peaking biquad filter in series; the real-time thread never allocates or locks.
- The pure logic (bands, conversion, presets, editing, settings, localization) and the audio processing are covered by automated tests.

### Uninstall

1. Quit EasyEQ and move `EasyEQ.app` to the Trash.
2. Delete presets: `~/Library/Application Support/EasyEQ`
3. Clear settings: `defaults delete app.easyeq.EasyEQ`

### License

[MIT](LICENSE)
