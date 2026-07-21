<p align="right">
  <strong>简体中文</strong> | <a href="./docs/README.en.md">English</a>
</p>

<div align="center">
  <img src="docs/img/logo.png" alt="NekoLink" width="100" />
</div>

<h1 align="center">NekoLink</h1>

<p align="center">
  <strong>原生 macOS 代理客户端</strong><br />
  基于 <a href="https://github.com/MetaCubeX/mihomo">Mihomo</a> 内核 · SwiftUI 构建 ·
  流畅不妥协
</p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-lightgrey?style=flat-square&logo=apple"></a>
  <a href="https://swift.org"><img alt="Swift 6.0" src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift"></a>
  <a href="#许可"><img alt="License-MIT" src="https://img.shields.io/badge/License-MIT-green?style=flat-square"></a>
  <a href="https://github.com/guokai/NekoLink/releases"><img alt="Release" src="https://img.shields.io/badge/Release-Pre--build-blue?style=flat-square"></a>
</p>


<div align="center">
  <img src="docs/img/screenshot.png" alt="NekoLink 截图" width="600" />
</div>

## 亮点

- **原生菜单栏** — `NSStatusBar` 手动管理菜单栏图标，`N` 字母图标，弹出面板支持节点切换 / 模式切换 / 延迟测试
- **Dashboard 主窗口** — 深色主题 + 光束背景，概览卡片聚合订阅/连接/日志/节点信息
- **订阅管理** — 添加 / 刷新 / 删除，定时自动刷新，流量用量仪表盘
- **并发延迟测试** — 渐变色徽章动画反馈，支持批量与单点测速
- **系统代理免密切换** — 通过 Helper Tool（XPC）免密设置，`networksetup` 实时读取状态
- **实时流量图** — WebSocket 推送，`Canvas` + `TimelineView` 60fps 渲染
- **日志查看器** — WebSocket 流式推送，级别过滤、文字搜索、自动滚动
- **活跃连接检视** — 可排序表格，搜索过滤，单条/批量强制断开
- **开机自启** · **暗色/浅色/跟随系统** · **Sparkle 2 自动更新** · **全局错误 Toast**



## 安装

> **尚未正式发布。** 可通过 [GitHub Releases](https://github.com/guokai/NekoLink/releases) 下载预构建版本，或按下方 [开发](#开发) 章节自行构建。

### 下载预构建包

```bash
# 1. 下载最新版 NekoLink-x.x.x.zip 并解压
# 2. 首次运行需绕过 Gatekeeper（因未签名）：
xattr -dr com.apple.quarantine NekoLink.app
# 3. 正常打开
open NekoLink.app
```

> 你也可以 **右键 → 打开**，在弹出的对话框中点击「打开」。

### 即将就绪

TUN 模式落地后，将通过 Developer ID 签名 + 公证提供正式版本，届时可直接双击运行。



## 开发

### 环境要求

- macOS 14+
- Xcode 16+（Swift 6.0）
- `mihomo` 通用二进制（arm64 / x86_64）

### 快速开始

```bash
# 放入 mihomo 内核（从 GitHub Releases 获取）
curl -L -o NekoLink/Resources/mihomo \
  https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-darwin-arm64
chmod +x NekoLink/Resources/mihomo

# 打开 Xcode 工程（已预生成，包含 extension target）
open NekoLink.xcodeproj
```

或者使用项目根目录的快速构建脚本（Debug 构建 + 自动重启）：

```bash
./preview.sh
```

### mihomo 二进制查找顺序

优先级从高到低：

1. App Bundle 内 `Resources/mihomo`
2. `~/.config/nekolink/mihomo`
3. `/opt/homebrew/bin/mihomo`
4. `/usr/local/bin/mihomo`



## 架构

```
SwiftUI 视图层（菜单栏弹出面板 + Dashboard 主窗口）
        │
        ▼
AppModel（全局状态，Observation）
        │
        ▼
Service 层
├─ CoreManager          → mihomo 进程托管
├─ MihomoAPI            → RESTful HTTP 客户端
├─ TrafficMonitor       → WebSocket 流量推送
├─ LogStream            → WebSocket 日志推送
├─ ConnectionMonitor    → WebSocket 连接推送
├─ SubscriptionService  → 订阅拉取 / 解析
├─ SystemProxyService   → Helper XPC 免密代理
├─ TunnelManager        → TUN 模式
├─ MenuBarManager       → NSStatusBar 菜单栏
├─ LaunchAtLoginService → SMAppService 开机自启
├─ AppearanceService    → 主题持久化
└─ UpdaterService       → Sparkle 2 自动更新
        │
        ▼
内核层：mihomo 二进制（Resources 内置）
```



## 路线图

> 当前里程碑：M0–M2 已完成，M4 打磨基本完成，待 M3 TUN 模式与 M5 公证发布。详见 [落地计划.md](./落地计划.md)。

### ✅ 已完成

- [x] 菜单栏 App（`MenuBarExtra`）+ 节点切换 / 模式切换 / 延迟测试
- [x] Dashboard 主窗口（深色主题 + 光束背景 + 概览卡片）
- [x] 订阅管理（增删改、定时自动刷新、流量用量仪表盘）
- [x] 系统代理免密切换（Helper Tool XPC）
- [x] 实时流量图（`Canvas` + `TimelineView` 60fps）
- [x] 日志查看器（流式、可过滤、可搜索）
- [x] 活跃连接管理（检视 / 搜索 / 批量强制断开）
- [x] Dock 图标常驻 + 点击恢复主窗口
- [x] 开机自启（`SMAppService`）
- [x] 暗色 / 浅色 / 跟随系统
- [x] 全局错误 Toast 提示
- [x] Sparkle 2 自动更新（已接入框架，待填 `SUPublicEDKey` + appcast）

### 🚧 进行中 & 规划中

- [ ] TUN 模式（`NetworkExtension` / `PacketTunnelProvider`）—— M3
- [ ] 可视化规则编辑器
- [ ] 多 profile 切换 + diff 预览
- [ ] iCloud 同步订阅
- [ ] Developer ID 签名公证 & 首个 GitHub Release —— M5



## 发布与自动更新

App 已集成 [Sparkle 2](https://sparkle-project.org/)，以下是完整发布流程。

### 1. 生成 EdDSA 密钥（一次性）

```bash
# 通过 SPM 拉到的 Sparkle 工具位于 ~/Library/Developer/Xcode/DerivedData/.../SourcePackages/artifacts/sparkle/...
# 推荐另装一份独立工具：
brew install --cask sparkle
generate_keys              # 私钥写入 Keychain；公钥打印到终端
```

将打印出的 EdDSA 公钥填入 `NekoLink/Info.plist` 的 `SUPublicEDKey`。

### 2. 配置 Feed 地址

`Info.plist` 中 `SUFeedURL` 默认为 `https://nekolink.app/appcast.xml`。按实际 Releases 站点替换。

### 3. 打包与签名 appcast

```bash
# 构建 Release，得到 NekoLink.app
xcodebuild -project NekoLink.xcodeproj -scheme NekoLink -configuration Release \
  -derivedDataPath build

# 用 Developer ID 签名 + 公证，产出 NekoLink-<ver>.zip
# 然后生成/更新 appcast：
generate_appcast ./releases/        # 目录里放所有历史版本 zip
```

将 `appcast.xml` 与 zip 一起上传到 `SUFeedURL` 指向的位置。

App 启动时会按 `SUScheduledCheckInterval`（默认 24h）自动检查；用户也可在 **菜单栏 → 检查更新** 或 **设置 → 关于 → 立即检查** 手动触发。



## 贡献

欢迎 Issue 与 PR！详见 [CONTRIBUTING.md](./CONTRIBUTING.md)，包含开发环境、代码规范与 PR checklist。



## 致谢

- [**Mihomo**](https://github.com/MetaCubeX/mihomo) — 真正干活的代理内核
- [**Yams**](https://github.com/jpsim/Yams) — YAML 解析
- [**Sparkle**](https://sparkle-project.org/) — 自动更新框架
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) — Xcode 工程生成



## 许可

[MIT](./LICENSE) © NekoLink contributors.