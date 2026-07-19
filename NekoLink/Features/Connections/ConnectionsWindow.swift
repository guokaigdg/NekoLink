import SwiftUI

struct ConnectionsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var sortOrder: [KeyPathComparator<ConnectionRow>] = [
        .init(\.duration, order: .forward)
    ]
    @State private var selection: Set<String> = []

    private struct ConnectionRow: Identifiable, Hashable {
        let id: String
        let host: String
        let dest: String
        let process: String
        let chain: String
        let rule: String
        let download: Int64
        let upload: Int64
        let start: Date

        var duration: TimeInterval { Date().timeIntervalSince(start) }
        var totalBytes: Int64 { download + upload }
    }

    private var rows: [ConnectionRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let mapped = model.connections.snapshot.connections.map { c in
            ConnectionRow(
                id: c.id,
                host: c.displayHost,
                dest: "\(c.metadata.destinationIP):\(c.displayPort)",
                process: c.processName,
                chain: c.chainSummary,
                rule: c.ruleSummary,
                download: c.download,
                upload: c.upload,
                start: c.start
            )
        }
        let filtered: [ConnectionRow]
        if q.isEmpty {
            filtered = mapped
        } else {
            filtered = mapped.filter { r in
                r.host.lowercased().contains(q)
                    || r.dest.lowercased().contains(q)
                    || r.process.lowercased().contains(q)
                    || r.rule.lowercased().contains(q)
                    || r.chain.lowercased().contains(q)
            }
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            table
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 460)
        .task {
            if model.coreRunning { model.connections.start() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("搜索 host / 进程 / 规则", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(model.connections.isConnected ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(model.connections.isConnected ? "已连接" : "未连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                let ids = selection
                Task {
                    for id in ids {
                        try? await model.api.closeConnection(id: id)
                    }
                    selection.removeAll()
                }
            } label: {
                Label("断开所选", systemImage: "xmark.circle")
            }
            .disabled(selection.isEmpty)

            Button(role: .destructive) {
                Task { try? await model.api.closeAllConnections() }
            } label: {
                Label("断开全部", systemImage: "xmark.octagon")
            }
            .disabled(rows.isEmpty)
        }
        .padding(12)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("主机", value: \.host) { r in
                Text(r.host).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 160, ideal: 220)

            TableColumn("目标", value: \.dest) { r in
                Text(r.dest).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180)

            TableColumn("进程", value: \.process) { r in
                Text(r.process).lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("链路", value: \.chain) { r in
                Text(r.chain).lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)

            TableColumn("规则", value: \.rule) { r in
                Text(r.rule).lineLimit(1).foregroundStyle(.secondary).font(.caption)
            }
            .width(min: 80, ideal: 130)

            TableColumn("↓", value: \.download) { r in
                Text(formatBytes(r.download))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .width(70)

            TableColumn("↑", value: \.upload) { r in
                Text(formatBytes(r.upload))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            .width(70)

            TableColumn("时长", value: \.duration) { r in
                Text(formatDuration(r.duration)).font(.caption.monospacedDigit())
            }
            .width(60)

            TableColumn("") { (r: ConnectionRow) in
                Button {
                    Task { try? await model.api.closeConnection(id: r.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("断开此连接")
            }
            .width(28)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    model.connections.isConnected ? "暂无活跃连接" : "未连接 mihomo",
                    systemImage: "network.slash"
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("活跃 \(rows.count)")
            Spacer()
            HStack(spacing: 12) {
                Label(formatBytes(model.connections.snapshot.downloadTotal), systemImage: "arrow.down")
                    .foregroundStyle(Color.accentColor)
                Label(formatBytes(model.connections.snapshot.uploadTotal), systemImage: "arrow.up")
                    .foregroundStyle(.orange)
            }
            .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m\(s % 60)s" }
    return "\(s / 3600)h\((s % 3600) / 60)m"
}
