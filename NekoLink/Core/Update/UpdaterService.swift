import Foundation
import Observation
import Sparkle

/// Sparkle 自动更新封装。
/// 启动时自动注册周期检查；UI 通过 `checkForUpdates()` 触发手动检查。
@Observable
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheck: Bool = true

    init() {
        // startingUpdater: true → 自动开始周期检查（依据 Info.plist 中的 SUScheduledCheckInterval）
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// 手动触发"检查更新"。会弹出 Sparkle 标准 UI。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 是否启用自动检查。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
