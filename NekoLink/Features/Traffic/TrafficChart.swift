import SwiftUI

/// 实时流量曲线：上行（橙）+ 下行（蓝）双区域填充曲线。
/// 使用 Canvas + TimelineView 做平滑滚动；纵轴自适应峰值。
struct TrafficChart: View {
    let samples: [TrafficSample]
    /// 视图保留的最大点数（应与 monitor.capacity 一致）。
    var capacity: Int = 60

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            Canvas { ctx, size in
                draw(into: &ctx, size: size, now: context.date)
            }
        }
    }

    // MARK: - 绘制

    private func draw(into ctx: inout GraphicsContext, size: CGSize, now: Date) {
        // 背景网格
        drawGrid(into: &ctx, size: size)

        guard samples.count >= 2 else { return }

        let peak = max(1024, samples.reduce(0) { max($0, max($1.up, $1.down)) }) // 最少 1KB/s 标尺
        let scaleY: (Double) -> Double = { v in
            let normalized = min(1, v / peak)
            return (1 - normalized) * size.height
        }

        // 时间窗 = capacity 秒，窗口右端跟随当前时间，做亚秒级滚动
        let windowSeconds = Double(capacity)
        let timeRight = now.timeIntervalSince1970
        let timeLeft = timeRight - windowSeconds
        let xFor: (Date) -> Double = { date in
            let t = date.timeIntervalSince1970
            let progress = (t - timeLeft) / windowSeconds
            return progress * size.width
        }

        // 下行（蓝）
        drawLine(
            into: &ctx,
            samples: samples,
            xFor: xFor,
            yFor: { scaleY($0.down) },
            stroke: Color.accentColor,
            fill: Color.accentColor.opacity(0.18),
            size: size
        )

        // 上行（橙）
        drawLine(
            into: &ctx,
            samples: samples,
            xFor: xFor,
            yFor: { scaleY($0.up) },
            stroke: Color.orange,
            fill: Color.orange.opacity(0.16),
            size: size
        )
    }

    private func drawGrid(into ctx: inout GraphicsContext, size: CGSize) {
        let lines = 3
        for i in 1...lines {
            let y = size.height * Double(i) / Double(lines + 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(
                path,
                with: .color(Color.secondary.opacity(0.12)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            )
        }
    }

    private func drawLine(
        into ctx: inout GraphicsContext,
        samples: [TrafficSample],
        xFor: (Date) -> Double,
        yFor: (TrafficSample) -> Double,
        stroke: Color,
        fill: Color,
        size: CGSize
    ) {
        var line = Path()
        var area = Path()
        var started = false

        for s in samples {
            let pt = CGPoint(x: xFor(s.timestamp), y: yFor(s))
            if !started {
                line.move(to: pt)
                area.move(to: CGPoint(x: pt.x, y: size.height))
                area.addLine(to: pt)
                started = true
            } else {
                line.addLine(to: pt)
                area.addLine(to: pt)
            }
        }

        if started, let last = samples.last {
            area.addLine(to: CGPoint(x: xFor(last.timestamp), y: size.height))
            area.closeSubpath()
        }

        ctx.fill(area, with: .color(fill))
        ctx.stroke(line, with: .color(stroke), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

/// 带速率读数的紧凑卡片（菜单栏使用）。
struct TrafficCard: View {
    let samples: [TrafficSample]
    let connected: Bool

    private var current: TrafficSample? { samples.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                rateLabel(
                    title: "↓",
                    color: .accentColor,
                    value: current?.down ?? 0
                )
                rateLabel(
                    title: "↑",
                    color: .orange,
                    value: current?.up ?? 0
                )
                Spacer()
                if !connected {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            TrafficChart(samples: samples)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
        }
    }

    private func rateLabel(title: String, color: Color, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(color).font(.callout.bold())
            Text(formatRate(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: value))
                .animation(.easeOut(duration: 0.25), value: value)
        }
    }
}
