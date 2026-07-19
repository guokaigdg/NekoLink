import AppKit
import SwiftUI

/// Dock 图标协调器：
/// - 始终显示 Dock 图标
/// - 点击 Dock 图标时打开主窗口
/// - 监听窗口状态
@MainActor
final class DockIconCoordinator: NSObject, ObservableObject {
    static let shared = DockIconCoordinator()

    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    func start() {
        // 始终显示 Dock 图标
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 打开主窗口
        showMainWindow()

        // 监听窗口事件
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification,
                                       object: nil, queue: .main) { notification in
            let window = notification.object as? NSWindow
            Task { @MainActor in
                DockIconCoordinator.shared.handleWindowClose(window)
            }
        })
    }

    func showMainWindow() {
        // 查找或创建主窗口
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 通过 SwiftUI 打开窗口
            NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
        }
    }

    private func handleWindowClose(_ window: NSWindow?) {
        guard let window = window else { return }

        // 如果是主窗口关闭，退出应用（可选）
        let identifier = window.identifier?.rawValue ?? ""
        if identifier.contains("main") {
            // 主窗口关闭时，最小化到 Dock 而不是退出
            // 用户可以点击 Dock 图标重新打开
        }
    }
}

// MARK: - AppDelegate 扩展

extension DockIconCoordinator: NSApplicationDelegate {
    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            DockIconCoordinator.shared.showMainWindow()
        }
        return true
    }

    nonisolated func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return nil
    }
}