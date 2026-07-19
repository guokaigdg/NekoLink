# Contributing to Catcat

Thanks for your interest. This document covers what you need to know before opening an issue or a pull request.

## Ground rules

- **Open an issue first** for non-trivial changes (new features, refactors, behavioral changes). Small fixes can go straight to a PR.
- **One PR, one concern.** Avoid bundling unrelated changes.
- **Keep diffs minimal.** Don't reformat untouched code or "improve" things outside your task.
- **Don't commit binaries.** `Catcat/Resources/mihomo`, `geo*.dat` and any signed artifacts are gitignored on purpose.

## Development setup

Requirements:

- macOS 14+
- Xcode 16+ (Swift 6.0)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A `mihomo` universal binary placed at `Catcat/Resources/mihomo`

```bash
xcodegen generate
open Catcat.xcodeproj
```

The `CatcatHelper` target is built and embedded automatically as a dependency of the main app.

## Code standards

- **Swift 6.0** with `SWIFT_STRICT_CONCURRENCY=complete`. Code must build cleanly with no concurrency warnings.
- **SwiftUI + Observation** (`@Observable`). Avoid `ObservableObject` / Combine unless interacting with legacy APIs.
- **Async/await first.** No `DispatchQueue.main.async` callback gymnastics.
- **No force-unwraps** in production paths. `try!` only acceptable in `#Preview`.
- **Naming**: types `UpperCamelCase`, members `lowerCamelCase`, files match the primary type they declare.

## Architecture pointers

- `Core/` — pure logic, no SwiftUI imports
  - `Mihomo/` — REST + WebSocket client and live monitors
  - `Subscription/` — fetch & YAML parse (Yams)
  - `SystemProxy/` — `networksetup` via privileged Helper Tool
  - `LaunchAtLogin/` — `SMAppService` wrapper
  - `CoreManager.swift` — supervises the `mihomo` subprocess
- `Features/` — SwiftUI views, one folder per feature
- `App/AppModel.swift` — top-level `@Observable` state aggregating all services
- `CatcatHelper/` — privileged XPC service; protocol lives in `Shared/HelperProtocol.swift`

When adding a new feature:

1. Put pure logic in `Core/<Feature>/`
2. Put views in `Features/<Feature>/`
3. Wire it into `AppModel` if it needs to be globally observable

## Pull request checklist

- [ ] Builds clean on Xcode 16 with strict concurrency
- [ ] No new force-unwraps / `try!` in production code
- [ ] No unrelated formatting or refactors
- [ ] Tested locally with a real subscription
- [ ] Updated `README.md` / `README.zh-CN.md` if user-facing behavior changed
- [ ] Updated `落地计划.md` if it touches roadmap milestones

## Reporting bugs

Include:

- macOS version & chip (Apple Silicon / Intel)
- Catcat version (`MARKETING_VERSION` in `project.yml` or About dialog)
- Mihomo version
- Steps to reproduce, expected vs actual
- Relevant log excerpts (Catcat log viewer or Console.app, redact secrets)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).
