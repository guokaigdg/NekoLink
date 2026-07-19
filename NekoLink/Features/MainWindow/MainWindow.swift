import SwiftUI
import NetworkExtension

/// 主窗口：大圆角 + 毛玻璃效果
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selectedItem: SidebarItem? = .home

    enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "概览"
        case subscriptions = "订阅"
        case connections = "连接"
        case logs = "日志"
        case settings = "设置"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: return "house"
            case .subscriptions: return "list.bullet.rectangle"
            case .connections: return "network"
            case .logs: return "doc.text.magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧边栏
            sidebar
                .frame(width: 240)
                .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))

            // 右侧内容
            detailView
        }
        .frame(minWidth: 900, minHeight: 600)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(16)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .help("刷新")
                .disabled(!model.coreRunning)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                if let imgURL = Bundle.main.url(forResource: "neko-link-logo", withExtension: "jpeg"),
                   let img = NSImage(contentsOf: imgURL) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                } else {
                    Image(systemName: "cat.fill")
                        .font(.title2)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("NekoLink")
                        .font(.title3.weight(.bold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.coreRunning ? Color.green : Color.secondary)
                            .frame(width: 5, height: 5)
                        Text(model.coreRunning ? "运行中" : "已停止")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 16)

            // 导航
            VStack(spacing: 6) {
                ForEach(SidebarItem.allCases) { item in
                    navItem(item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Spacer()
        }
    }

    private func navItem(_ item: SidebarItem) -> some View {
        let isSelected = selectedItem == item

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedItem = item
            }
        } label: {
            Label(item.rawValue, systemImage: item.icon)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .home:
            HomeView()
                .environment(model)

        case .subscriptions:
            SubscriptionsWindow()
                .environment(model)
                .padding(.top, 8)
                .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))

        case .connections:
            ConnectionsWindow()
                .environment(model)
                .padding(.top, 8)
                .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))

        case .logs:
            LogsWindow()
                .environment(model)
                .padding(.top, 8)
                .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))

        case .settings:
            SettingsView()
                .environment(model)
                .padding(.top, 8)
                .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))

        case .none:
            ContentUnavailableView(
                "NekoLink",
                systemImage: "cat",
                description: Text("从左侧选择功能")
            )
        }
    }
}

// MARK: - Visual Effect

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { model.appearance.mode },
                    set: { model.appearance.mode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.segmented)

                Toggle("开机自动启动", isOn: Binding(
                    get: { model.launchAtLogin.isEnabled },
                    set: { model.launchAtLogin.setEnabled($0) }
                ))
                if model.launchAtLogin.requiresApproval {
                    Button("在系统设置中批准…") {
                        model.launchAtLogin.openSystemSettings()
                    }
                }
            } header: {
                Label("通用", systemImage: "switch.2")
            }

            Section {
                HStack {
                    Text("自动刷新间隔")
                    Spacer()
                    TextField("", value: Binding(
                        get: { model.subscriptions.autoRefreshInterval / 3600 },
                        set: { model.subscriptions.autoRefreshInterval = $0 * 3600 }
                    ), format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    Text("小时").foregroundStyle(.secondary)
                }
            } header: {
                Label("订阅", systemImage: "list.bullet.rectangle")
            }

            Section {
                LabeledContent {
                    HStack(spacing: 4) {
                        Circle().fill(model.systemProxy.isEnabled ? Color.green : Color.secondary).frame(width: 6, height: 6)
                        Text(model.systemProxy.isEnabled ? "已启用" : "已禁用")
                    }
                } label: {
                    Label("状态", systemImage: "globe")
                }
                LabeledContent {
                    Text("\(model.systemProxy.proxyHost):\(model.systemProxy.proxyPort)")
                        .monospacedDigit()
                } label: {
                    Label("地址", systemImage: "network")
                }
            } header: {
                Label("系统代理", systemImage: "globe")
            }

            Section {
                Toggle("自动检查更新", isOn: Binding(
                    get: { model.updater.automaticallyChecksForUpdates },
                    set: { model.updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent {
                    Button("立即检查…") {
                        model.updater.checkForUpdates()
                    }
                } label: {
                    Label("更新", systemImage: "arrow.down.circle")
                }
                LabeledContent("0.1.0") {
                    Text("0.1.0").foregroundStyle(.secondary)
                }
            } header: {
                Label("关于", systemImage: "info.circle")
            }

            Section {
                Toggle("TUN 模式", isOn: Binding(
                    get: { model.tunnel.isEnabled },
                    set: { _ in Task { await model.tunnel.toggle() } }
                ))
                if model.tunnel.isEnabled {
                    LabeledContent {
                        Text(tunnelStatusText(model.tunnel.status))
                            .foregroundStyle(statusColor(model.tunnel.status))
                    } label: {
                        Label("状态", systemImage: "network.badge.shield.half.filled")
                    }
                }
                if !model.tunnel.isAvailable && !model.tunnel.isEnabled {
                    Text("TUN 模式需要开发者签名后使用 NetworkExtension")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("TUN", systemImage: "shield.righthalf.filled")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - TUN 状态辅助

    private func tunnelStatusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:     return "未配置"
        case .disconnected: return "未连接"
        case .connecting:  return "连接中…"
        case .connected:   return "已连接"
        case .reasserting: return "重连中…"
        case .disconnecting: return "断开中…"
        @unknown default:  return "未知"
        }
    }

    private func statusColor(_ status: NEVPNStatus) -> Color {
        switch status {
        case .connected:   return .green
        case .connecting, .reasserting: return .orange
        case .disconnecting: return .yellow
        default:           return .secondary
        }
    }
}

// MARK: - Preview

#Preview("MainWindow") {
    MainWindow()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}