import SwiftUI

/// 全局错误提示。监听 `AppModel.lastError` 与 `SubscriptionService.lastError`，
/// 一次性展示 3 秒后自动消失。多次触发以最新一条为准。
struct ErrorToastModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    @State private var current: String?
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let msg = current {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .padding(.bottom, 12)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: current)
            .onChange(of: model.lastError) { _, new in
                show(new)
            }
            .onChange(of: model.subscriptions.lastError) { _, new in
                show(new)
            }
    }

    private func show(_ msg: String?) {
        guard let msg, !msg.isEmpty else { return }
        current = msg
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                await MainActor.run { dismiss() }
            }
        }
    }

    private func dismiss() {
        current = nil
        // 清掉源 lastError，避免相同消息无法再次触发
        model.lastError = nil
        model.subscriptions.clearLastError()
    }
}

extension View {
    func errorToast() -> some View { modifier(ErrorToastModifier()) }
}
