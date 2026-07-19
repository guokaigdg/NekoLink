import SwiftUI

struct LogsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var displayLevel: LogLevel = .info
    @State private var search = ""
    @State private var autoScroll = true

    private var filtered: [LogEntry] {
        let entries = model.logs.entries
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { e in
            guard e.level.rank >= displayLevel.rank else { return false }
            if !q.isEmpty, !e.message.lowercased().contains(q) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            if model.coreRunning { model.logs.start() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("订阅级别", selection: Binding(
                get: { model.logs.subscribeLevel },
                set: { model.logs.subscribeLevel = $0 }
            )) {
                ForEach(LogLevel.allCases) { l in
                    Text(l.label).tag(l)
                }
            }
            .frame(width: 140)
            .help("WebSocket 订阅级别（决定从 mihomo 拉取的最低级别）")

            Picker("显示", selection: $displayLevel) {
                ForEach(LogLevel.allCases) { l in
                    Text(l.label).tag(l)
                }
            }
            .frame(width: 120)
            .help("客户端显示过滤")

            TextField("搜索", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(model.logs.isConnected ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(model.logs.isConnected ? "已连接" : "未连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("自动滚动", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Button {
                model.logs.clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .help("清空当前缓存")
        }
        .padding(12)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { entry in
                        LogRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: filtered.last?.id) { _, newID in
                guard autoScroll, let id = newID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    reader.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timestampString)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            LevelBadge(level: entry.level)
                .frame(width: 56, alignment: .leading)
            Text(entry.message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var timestampString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: entry.timestamp)
    }
}

private struct LevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }

    private var color: Color {
        switch level {
        case .debug:   return .secondary
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
