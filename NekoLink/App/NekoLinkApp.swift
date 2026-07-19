import AppKit
import SwiftUI

@main
struct NekoLinkApp: App {
    @State private var model = AppModel()
    @State private var menuBarManager = MenuBarManager()

    var body: some Scene {
        // 主窗口：聚合所有功能，点击 Dock 图标显示
        Window("NekoLink", id: "main") {
            MainWindow()
                .environment(model)
                .preferredColorScheme(model.appearance.mode.colorScheme)
                .task {
                    // 启动菜单栏和 Dock 图标管理
                    setupServices()
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            // 添加菜单命令
            CommandGroup(replacing: .newItem) {
                Button("刷新订阅") {
                    Task { await model.subscriptions.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    @MainActor
    private func setupServices() {
        // 确保 Dock 图标显示
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DockIconCoordinator.shared.start()
        menuBarManager.start(with: model)
    }
}