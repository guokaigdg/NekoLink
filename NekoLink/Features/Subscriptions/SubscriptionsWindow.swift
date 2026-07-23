import SwiftUI

struct SubscriptionsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var showAddSheet = false
    @State private var refreshingAll = false

    @Namespace private var namespace

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 400, ideal: 520)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus.circle.fill")
                }

                Button {
                    Task {
                        refreshingAll = true
                        await model.subscriptions.refreshAll()
                        refreshingAll = false
                    }
                } label: {
                    Label("全部刷新", systemImage: "arrow.clockwise.circle.fill")
                        .symbolEffect(.pulse, isActive: refreshingAll)
                }
                .disabled(model.subscriptions.subscriptions.isEmpty || refreshingAll)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSubscriptionSheet { name, url in
                Task { await model.subscriptions.add(name: name, url: url) }
            }
        }
        .frame(minWidth: 740, minHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(model.subscriptions.subscriptions) { sub in
                SubscriptionRow(
                    subscription: sub,
                    isActive: model.subscriptions.activeID == sub.id,
                    namespace: namespace
                )
                .tag(sub.id)
                .contextMenu {
                    Button {
                        Task { await model.activateSubscription(sub.id) }
                    } label: {
                        Label("激活", systemImage: "checkmark.seal.fill")
                    }

                    Button {
                        Task { await model.refreshSubscription(sub.id) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise.circle.fill")
                    }

                    Divider()

                    Button(role: .destructive) {
                        if selection == sub.id { selection = nil }
                        model.subscriptions.remove(sub.id)
                    } label: {
                        Label("删除", systemImage: "trash.circle.fill")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.subscriptions.subscriptions.isEmpty {
                ContentUnavailableView {
                    Label("暂无订阅", systemImage: "tray.full")
                        .font(.largeTitle)
                        .symbolEffect(.pulse, isActive: true)
                } description: {
                    Text("点击右上角 + 添加")
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection,
           let sub = model.subscriptions.subscriptions.first(where: { $0.id == id }) {
            SubscriptionDetail(
                subscription: sub,
                namespace: namespace
            )
            .id(sub.id)
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
        } else {
            ContentUnavailableView("选择一项查看详情", systemImage: "list.bullet.rectangle.portrait")
                .font(.largeTitle)
        }
    }
}

// MARK: - Sidebar Row

private struct SubscriptionRow: View {
    let subscription: Subscription
    let isActive: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: isActive ? "checkmark.seal.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .symbolEffect(.pulse, isActive: isActive)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Text(subscription.updatedAt.map(Self.relative) ?? "未刷新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let info = subscription.userInfo {
                TrafficBadge(info: info)
            }

            if isActive {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: true)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
                .animation(.easeInOut(duration: 0.3), value: isActive)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return "已更新 " + f.localizedString(for: date, relativeTo: Date())
    }
}

private struct TrafficBadge: View {
    let info: Subscription.UserInfo
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
                .foregroundStyle(info.usedRatio > 0.8 ? .red : .secondary)

            Text("\(info.usedRatio * 100, format: .number.precision(.fractionLength(0)))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(info.usedRatio > 0.8 ? .red : .secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(info.usedRatio > 0.8 ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Detail Pane

private struct SubscriptionDetail: View {
    @Environment(AppModel.self) private var model
    let subscription: Subscription
    let namespace: Namespace.ID
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let info = subscription.userInfo {
                    trafficCard(info)
                }
                metaCard
                actionButtons
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: model.subscriptions.activeID == subscription.id
                                    ? [.accentColor.opacity(0.2), .accentColor.opacity(0.1)]
                                    : [.secondary.opacity(0.1), .secondary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: model.subscriptions.activeID == subscription.id
                          ? "checkmark.seal.fill"
                          : "doc.text.fill")
                        .font(.largeTitle)
                        .foregroundStyle(model.subscriptions.activeID == subscription.id
                                          ? Color.accentColor
                                          : .secondary)
                        .symbolEffect(.pulse, isActive: model.subscriptions.activeID == subscription.id)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.name)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text(subscription.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if model.subscriptions.activeID == subscription.id {
                    Label("已激活", systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .symbolEffect(.pulse, isActive: true)
                }
            }

            Divider()
        }
    }

    private func trafficCard(_ info: Subscription.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("流量统计", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(formatBytes(info.used)) / \(formatBytes(info.total))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            ProgressView(value: info.usedRatio)
                .progressViewStyle(.linear)
                .tint(progressTint(info.usedRatio))
                .scaleEffect(y: 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: info.usedRatio)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 16) {
                metricGrid("上传", value: formatBytes(info.upload), icon: "arrow.up.circle.fill", color: .blue)
                metricGrid("下载", value: formatBytes(info.download), icon: "arrow.down.circle.fill", color: .green)
                metricGrid("剩余", value: formatBytes(info.remaining), icon: "minus.circle.fill", color: .secondary)
                if let expire = info.expireDate {
                    metricGrid("到期", value: expire.formatted(date: .abbreviated, time: .omitted), icon: "calendar.circle.fill", color: .orange)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func metricGrid(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("详细信息", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                metaRow("最后更新", subscription.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—", icon: "clock")
                metaRow("本地路径", model.subscriptions.profileURL(for: subscription.id).path, icon: "folder.fill")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func metaRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    refreshing = true
                    await model.refreshSubscription(subscription.id)
                    refreshing = false
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise.circle.fill")
                    .font(.body.weight(.semibold))
                    .symbolEffect(.pulse, isActive: refreshing)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(refreshing)
            .buttonStyle(.plain)

            Button {
                Task { await model.activateSubscription(subscription.id) }
            } label: {
                Label("激活", systemImage: "bolt.circle.fill")
                    .font(.body.weight(.semibold))
                    .symbolEffect(.pulse, isActive: true)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(model.subscriptions.activeID == subscription.id)
            .keyboardShortcut(.return)
            .buttonStyle(.plain)

            Spacer()

            Button(role: .destructive) {
                model.subscriptions.remove(subscription.id)
            } label: {
                Label("删除", systemImage: "trash.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.red.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func progressTint(_ ratio: Double) -> Color {
        switch ratio {
        case ..<0.7: return .green
        case ..<0.9: return .orange
        default:     return .red
        }
    }
}

// MARK: - Add Sheet

private struct AddSubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var urlText: String = ""

    let onAdd: (String, URL) -> Void

    private var url: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed),
              let scheme = u.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            return nil
        }
        return u
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && url != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: true)

                Text("添加订阅")
                    .font(.title3.bold())
            }

            Form {
                Section {
                    TextField("名称", text: $name)
                        .textFieldStyle(.plain)
                } header: {
                    Label("订阅名称", systemImage: "text.alignleft")
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("订阅 URL", text: $urlText)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                } header: {
                    Label("订阅地址", systemImage: "link")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("添加") {
                    if let url {
                        onAdd(name.trimmingCharacters(in: .whitespaces), url)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return f.string(fromByteCount: bytes)
}