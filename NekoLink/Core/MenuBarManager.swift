import AppKit
import SwiftUI

/// 手动管理菜单栏图标（NSStatusItem），替代 SwiftUI 的 MenuBarExtra。
///
/// MenuBarExtra 会自动将激活策略改为 .accessory 从而隐藏 Dock 图标，
/// 使用 NSStatusBar 手动创建可以在保留 Dock 图标的同时显示菜单栏图标。
@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appModel: AppModel?

    func start(with model: AppModel) {
        appModel = model

        let item = NSStatusBar.system.statusItem(withLength: 24)
        item.button?.image = Self.makeNLetterImage()
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 640)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(model)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // 确保弹出窗口尺寸固定，防止被 SwiftUI 内容压缩
            popover.contentSize = NSSize(width: 320, height: 640)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // 弹出后再设置一次，覆盖 SwiftUI 的自动尺寸调整
            popover.contentSize = NSSize(width: 320, height: 640)
            // 确保 popover 成为关键窗口以接收键盘事件
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 更新菜单栏图标（根据 core 运行状态）
    func updateIcon(running: Bool) {
        // 暂时都用相同的 N 字母图标，后续可区分状态
        statusItem?.button?.image = Self.makeNLetterImage()
    }

    // MARK: - 图标生成

    /// 生成一个 "N" 字母图标，用于菜单栏显示
    private static func makeNLetterImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        // 使用 attributed string 绘制，通过 bounding rect 精确居中
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.controlTextColor,
        ]
        let attrStr = NSAttributedString(string: "N", attributes: attrs)
        let textSize = attrStr.size()

        // 计算绘制区域，让文字精确居中
        let drawRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrStr.draw(in: drawRect)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    func stop() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover = nil
    }
}