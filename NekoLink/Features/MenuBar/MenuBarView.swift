import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.coreRunning {
                TrafficCard(samples: model.traffic.samples, connected: model.traffic.isConnected)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Divider()
                systemProxyRow
                Divider()
                if model.tunnel.isEnabled {
                    tunStatusRow
                    Divider()
                }
            }
            modeSection
            Divider()
            proxiesSection
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(.vertical, 8)
        .task {
            await model.syncSystemProxyPort()
            await model.systemProxy.refreshStatus()
            if model.coreRunning {
                model.traffic.start()
                model.logs.start()
                model.connections.start()
                await model.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: model.coreRunning ? "circle.fill" : "circle")
                .foregroundStyle(model.coreRunning ? .green : .secondary)
                .symbolEffect(.pulse, isActive: model.coreRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text("NekoLink").font(.headline)
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.coreRunning },
                set: { _ in Task { await model.toggleCore() } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - System Proxy

    private var systemProxyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.systemProxy.isEnabled ? "globe.badge.chevron.backward" : "globe")
                .foregroundStyle(model.systemProxy.isEnabled ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("设为系统代理").font(.callout)
                Text(model.systemProxy.helperInstalled
                     ? "\(model.systemProxy.proxyHost):\(model.systemProxy.proxyPort)"
                     : "首次启用需授权安装 Helper")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.systemProxy.isEnabled },
                set: { _ in Task { await model.systemProxy.toggle() } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - TUN Status

    private var tunStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.righthalf.filled")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("TUN 模式").font(.callout)
                Text("已启用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Mode

    private var modeSection: some View {
        HStack(spacing: 8) {
            ForEach(TunnelMode.allCases, id: \.self) { mode in
                ModePill(
                    title: mode.label,
                    selected: model.currentMode == mode
                ) {
                    Task { await model.switchMode(mode) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(!model.coreRunning)
        .opacity(model.coreRunning ? 1 : 0.5)
    }

    // MARK: - Proxies

    private var proxiesSection: some View {
        Group {
            if model.proxies.isEmpty {
                Text(model.coreRunning ? "暂无策略组" : "启动后查看节点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.proxies) { group in
                            GroupRow(group: group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!model.coreRunning)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("主窗口", systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.borderless)

            Button {
                model.updater.checkForUpdates()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("检查更新", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .font(.caption)
    }

}

// MARK: - 子组件

private struct ModePill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(selected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
    }
}

private struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ProxyGroup
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(group.name).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(group.now ?? "-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    Task { await model.testGroup(group) }
                } label: {
                    Image(systemName: model.testingGroups.contains(group.name)
                          ? "bolt.fill"
                          : "bolt")
                        .font(.caption2)
                        .foregroundStyle(model.testingGroups.contains(group.name)
                                         ? Color.accentColor
                                         : Color.secondary)
                        .symbolEffect(.pulse, isActive: model.testingGroups.contains(group.name))
                }
                .buttonStyle(.plain)
                .help("测速")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.members) { item in
                        ProxyItemRow(group: group.name, item: item, selected: item.name == group.now)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ProxyItemRow: View {
    @Environment(AppModel.self) private var model
    let group: String
    let item: ProxyItem
    let selected: Bool

    var body: some View {
        Button {
            Task {
                try? await model.api.selectProxy(group: group, name: item.name)
                await model.refresh()
            }
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(item.name).font(.caption)
                Spacer()
                if let d = effectiveDelay {
                    Text(d == 0 ? "超时" : "\(d) ms")
                        .font(.caption2)
                        .foregroundStyle(delayColor(d))
                        .contentTransition(.numericText())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("单独测速") {
                Task { await model.testNode(item.name) }
            }
        }
    }

    private var effectiveDelay: Int? {
        // 优先用 AppModel 实时测速结果；其次 fallback 到 history。
        if let d = model.delays[item.name] { return d }
        return item.latestDelay
    }

    private func delayColor(_ ms: Int) -> Color {
        switch ms {
        case 0:        return .secondary
        case 1..<200:  return .green
        case 200..<500: return .orange
        default:       return .red
        }
    }
}
