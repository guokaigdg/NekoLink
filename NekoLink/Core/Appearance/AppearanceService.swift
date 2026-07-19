import Foundation
import Observation
import SwiftUI

/// 外观模式：跟随系统 / 浅色 / 深色。
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    /// 转换为 SwiftUI 的 `preferredColorScheme` 参数；
    /// `.system` 返回 nil，表示不覆盖系统偏好。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// 全局外观偏好。UserDefaults 持久化。
@Observable
@MainActor
final class AppearanceService {
    private static let defaultsKey = "NekoLink.AppearanceMode"

    var mode: AppearanceMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        self.mode = AppearanceMode(rawValue: raw) ?? .system
    }
}
