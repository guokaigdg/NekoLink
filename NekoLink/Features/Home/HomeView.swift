import SwiftUI

/// 功能聚合 Dashboard：订阅 / 连接 / 日志 / 设置 概览卡片
struct HomeView: View {
    @Environment(AppModel.self) private var model

    @State private var beamsVisible = false
    @State private var heroVisible = false
    @State private var cardsVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                beamRight(in: geo)
                    .opacity(beamsVisible ? 1 : 0)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(24, geo.size.height * 0.04))

                        heroSection
                            .opacity(heroVisible ? 1 : 0)
                            .offset(y: heroVisible ? 0 : 20)

                        dashboardGrid
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)
                            .padding(.top, 32)
                            .padding(.bottom, 40)

                        Spacer()
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 28)
                }
            }
        }
        .onAppear {
            startEntranceAnimation()
            Task { await model.systemProxy.refreshStatus() }
        }
    }

    // MARK: - Entrance Animation

    private func startEntranceAnimation() {
        withAnimation(.easeOut(duration: 0.7)) { heroVisible = true }
        withAnimation(.easeOut(duration: 0.7).delay(0.15)) { cardsVisible = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 1.2)) { beamsVisible = true }
        }
    }

    // MARK: - Beams

    private func beamLeft(in geo: GeometryProxy) -> some View {
        let w = geo.size.width * 0.55
        let h = geo.size.height * 0.7
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 160 / 255, green: 205 / 255, blue: 255 / 255).opacity(0.70), location: 0.0),
                .init(color: Color(red: 70 / 255, green: 135 / 255, blue: 235 / 255).opacity(0.35), location: 0.55),
                .init(color: .clear, location: 0.85),
            ]),
            center: .center, startRadius: 0, endRadius: max(w, h) * 0.5
        )
        .frame(width: w, height: h)
        .rotationEffect(.degrees(20), anchor: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .blur(radius: 80)
        .allowsHitTesting(false)
    }

    private func beamRight(in geo: GeometryProxy) -> some View {
        let w = geo.size.width * 0.55
        let h = geo.size.height * 0.7
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 160 / 255, green: 205 / 255, blue: 255 / 255).opacity(0.70), location: 0.0),
                .init(color: Color(red: 70 / 255, green: 135 / 255, blue: 235 / 255).opacity(0.35), location: 0.55),
                .init(color: .clear, location: 0.85),
            ]),
            center: .center, startRadius: 0, endRadius: max(w, h) * 0.5
        )
        .frame(width: w, height: h)
        .rotationEffect(.degrees(-20), anchor: .topTrailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .blur(radius: 80)
        .allowsHitTesting(false)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NekoLink")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.75), .white.opacity(0.45)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .tracking(-1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.coreRunning ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(model.statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                coreToggleButton
            }

            // 快捷操作栏
            HStack(spacing: 10) {
                ModePillDashboard(title: "规则", active: model.currentMode == .rule) {
                    Task { await model.switchMode(.rule) }
                }
                ModePillDashboard(title: "全局", active: model.currentMode == .global) {
                    Task { await model.switchMode(.global) }
                }
                ModePillDashboard(title: "直连", active: model.currentMode == .direct) {
                    Task { await model.switchMode(.direct) }
                }

                Spacer()

                systemProxyBadge
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var coreToggleButton: some View {
        Button {
            Task { await model.toggleCore() }
        } label: {
            HStack(spacing: 6) {
                Text(model.coreRunning ? "停止" : "启动")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: model.coreRunning ? "stop.fill" : "power")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: model.coreRunning
                        ? [Color.red.opacity(0.7), Color.red.opacity(0.5)]
                        : [Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255),
                           Color(red: 6 / 255, green: 182 / 255, blue: 212 / 255)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var systemProxyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: model.systemProxy.isEnabled ? "globe.badge.chevron.backward" : "globe")
                .font(.system(size: 12))
                .foregroundStyle(model.systemProxy.isEnabled ? Color.accentColor : .white.opacity(0.4))
            Text(model.systemProxy.isEnabled ? "系统代理：开" : "系统代理：关")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.systemProxy.isEnabled ? Color.accentColor : .white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        .onTapGesture {
            Task { await model.systemProxy.toggle() }
        }
    }

    // MARK: - Dashboard Grid

    private var dashboardGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            subscriptionCard
            connectionsCard
            logsCard
            settingsCard
        }
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        DashboardCard(icon: "list.bullet.rectangle", title: "订阅", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(model.subscriptions.subscriptions.count) 个订阅")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }

                if let active = model.subscriptions.subscriptions.first(where: { $0.id == model.subscriptions.activeID }),
                   let info = active.userInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(active.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(byteString(info.used))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(.white.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, g.size.width * CGFloat(info.usedRatio)), height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("剩余 \(byteString(info.remaining))")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            if let expire = info.expireDate {
                                Text("到期 \(relativeTime(expire))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                } else {
                    Text("暂无激活订阅")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()
            }
        }
    }

    // MARK: - Connections Card

    private var connectionsCard: some View {
        DashboardCard(icon: "network", title: "连接", color: .green) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(model.connections.snapshot.connections.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("活跃")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 8)
                    Spacer()
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下载")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(0.5)
                        Text(byteString(model.connections.snapshot.downloadTotal))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上传")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(0.5)
                        Text(byteString(model.connections.snapshot.uploadTotal))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                }

                Spacer()
            }
        }
    }

    // MARK: - Logs Card

    private var logsCard: some View {
        DashboardCard(icon: "doc.text.magnifyingglass", title: "日志", color: .orange) {
            VStack(alignment: .leading, spacing: 0) {
                let recent = Array(model.logs.entries.suffix(5).reversed())
                if recent.isEmpty {
                    Spacer()
                    Text("暂无日志")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recent) { entry in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(logColor(entry.level))
                                    .frame(width: 5, height: 5)
                                Text(entry.message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Settings / Nodes Card

    private var settingsCard: some View {
        DashboardCard(icon: "gearshape", title: "节点 & 设置", color: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                if let group = model.proxies.first(where: { $0.type == "Selector" || $0.type == "select" }) {
                    HStack {
                        Text(group.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(group.now ?? "—")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    Divider().background(.white.opacity(0.06))
                }

                HStack(spacing: 12) {
                    LabeledValue(label: "系统代理", value: model.systemProxy.isEnabled ? "已启用" : "已禁用",
                                 active: model.systemProxy.isEnabled)
                    LabeledValue(label: "监听端口", value: "\(model.systemProxy.proxyPort)")
                    LabeledValue(label: "自启动", value: model.launchAtLogin.isEnabled ? "已启用" : "已禁用",
                                 active: model.launchAtLogin.isEnabled)
                    Spacer()
                }

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:   return .gray
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sub-components

private struct ModePillDashboard: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.18) : .white.opacity(0.06))
                )
                .foregroundStyle(active ? Color.accentColor : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(!model.coreRunning)
    }

    @Environment(AppModel.self) private var model
}

private struct DashboardCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(.white.opacity(0.06))

            content
                .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(minHeight: 180)
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String
    var active: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(0.3)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.green.opacity(0.9) : .white.opacity(0.7))
        }
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    let model = AppModel()
    return HomeView()
        .environment(model)
        .frame(width: 800, height: 600)
}
