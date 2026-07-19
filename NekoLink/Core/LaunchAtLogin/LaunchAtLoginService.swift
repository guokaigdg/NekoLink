import Foundation
import Observation
import ServiceManagement

/// 登录项管理：基于 SMAppService.mainApp，macOS 13+。
/// 注：仅在已签名（Developer ID 或 ad-hoc）且 App 位于 ~/Applications 或 /Applications
/// 这类系统识别位置时，注册才会真正生效。
@Observable
@MainActor
final class LaunchAtLoginService {

    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init() { refresh() }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "\(error)"
        }
        refresh()
    }

    /// 当 status == .requiresApproval 时调用，跳到「系统设置 - 通用 - 登录项」。
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
