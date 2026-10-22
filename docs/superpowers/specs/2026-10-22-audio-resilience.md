# EasyEQ 音频容错（Audio Resilience）设计

日期：2026-10-22
状态：作者已同意（“来做吧”）

## 背景（真实事故）

2026-10-22 01:00:58，苹果的 USB 音频驱动服务 `com.apple.usbaudiod`（驱动 Studio Display 扬声器）在 EasyEQ 测试实例正通过私有聚合设备使用 Studio Display 时重启。之后 `coreaudiod` 在销毁该聚合设备的 IO 上下文时，对已失效驱动连接的 Mach 消息每 30 秒超时一次（`0x10000004`），整个音频服务卡死，直到用户手动重启 `coreaudiod`。根因在 macOS 内部，EasyEQ 无法根治，但可以降低概率、缩短影响、并提供一键恢复。

## 目标

1. **一键修复系统声音**：当 EasyEQ 判定 Core Audio 无响应（构建看门狗超时）时，底部除“重试”外再显示“修复系统声音”。点击后通过 macOS 自带的管理员授权框（`osascript` 的 `do shell script "killall coreaudiod" with administrator privileges`）重启音频服务；EasyEQ 不接触密码。成功后约 2 秒自动重试启动。用户取消授权 → 什么都不做；失败 → 本地化错误提示。
2. **驱动掉线时立刻让开**：监听当前输出设备的 `kAudioDevicePropertyDeviceIsAlive` 和系统设备列表 `kAudioHardwarePropertyDevices`。当输出设备“不再存活”或从设备列表消失（驱动重启的表现）时，立即在后台队列拆除管线（先销毁 tap，恢复系统原声），然后等设备重新出现 / 默认输出变化后再（去抖）重建。
3. **减少不必要的重建**：只有在“默认输出设备 UID”或“采样率”确实变化、设备掉线 / 恢复、用户点重试、启动失败后切回 App 时才重建；与当前管线无关的设备列表变化（比如插拔别的设备）不触发重建。多次事件在 300 ms 内合并为一次。

## 非目标
- 不尝试绕过或修补 `coreaudiod` / `usbaudiod`。
- 不在后台自动重启 `coreaudiod`（必须用户点击并授权）。
- 不改变 EQ 处理、UI 其他部分。

## 文案（中 / 英，两份字符串表都要有）
| key | zh-Hans | en |
|---|---|---|
| engine.repair | 修复系统声音 | Repair System Audio |
| engine.unresponsive | 系统音频服务没有响应。 | The system audio service isn't responding. |
| error.repairFailed | 系统声音修复失败。 | Couldn't repair system audio. |

（看门狗超时时，底部显示 `engine.unresponsive` + “重试” + “修复系统声音”；其他失败仍显示原来的 `engine.failed` + “重试”。）

## 验收
1. 看门狗超时后出现“修复系统声音”；点击弹出系统管理员授权框；取消不报错；授权后音频服务重启、EasyEQ 自动重试并进入运行状态。
2. 输出设备掉线（拔掉 USB 音频设备 / 驱动重启）时，日志显示立即拆除管线、系统声音恢复原样；设备回来后自动重建。
3. 插拔与当前输出无关的设备不触发重建（日志可见）。
4. `swift test` 全部通过；纯逻辑（重建判定、失败类型判定）有单元测试。
