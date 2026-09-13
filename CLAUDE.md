# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and test

```bash
xcodebuild test -project Broke.xcodeproj -scheme Broke \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' CODE_SIGNING_ALLOWED=NO
```

`BrokeTests` is an XCTest bundle hosted by the app, so it inherits the App Group and
Family Controls entitlements. Subclass `BrokeTestCase`: it points `SharedStore.defaults`
at a scratch suite and `ScheduleManager`'s two injection points at recorders, then puts
all three back. Tests cannot build an `ApplicationToken`, so every fixture profile carries
empty token sets.

```bash
xcodebuild -project Broke.xcodeproj -scheme Broke \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

Build `-configuration Release` as well after touching anything inside `#if DEBUG`.

Run on a device from Xcode (⌘R uses the Debug configuration). Two behaviors do not work in the simulator: `DeviceActivityMonitor` callbacks never fire, and NFC is unavailable.

Bundle ID `com.Brokeest.ios`, App Group `group.com.Brokeest.ios`, deployment target iOS 16.4.

## Targets and shared files

Four targets: the app `Broke`, the `BrokeMonitor` monitor extension, and the `BrokeShieldConfig` / `BrokeShieldAction` shield extensions.

`SharedStore.swift`, `Schedule.swift`, `ShieldWriter.swift`, and `HardeningManager.swift` are members of both the app and `BrokeMonitor`. Code they contain must compile against the extension too, so it cannot reference SwiftUI views or app-only types.

Adding a new file means editing `project.pbxproj` for every target that needs it. Prefer extending one of the shared files above over creating a new dual-target file.

## Architecture

**Shield sources compose, they do not overwrite.** Each schedule owns a `ManagedSettingsStore` named by its UUID; the manual tag toggle owns the `"broke"` store; device restrictions live in `"broke-hardening"`. The system combines settings from separate stores, so one source can never clear another's shield. Anything that decides what is blocked writes through `ShieldWriter`.

**The App Group carries all state**, since the app and the extension are separate processes. `SharedStore` is the only way in: profiles, current profile, manual blocking flag, suspension deadline, emergency unblock count, profile edit grant, and the log buffer.

**Two processes recompute the same decision.** `Schedule.effectiveWantsBlock()` is the single source of truth. `ScheduleManager.sync(profiles:)` applies it in the app after any change and at launch; `DeviceActivityMonitorExtension` applies it on every callback. Both recompute state from scratch rather than assume which edge fired, because `DeviceActivitySchedule` has no weekday parameter and fires daily.

**Mode semantics.** A schedule is "usable" when today is one of its `weekdays` and now is inside the window. `.block` blocks while usable. `.allow` blocks whenever it is not usable, which includes entire days not in `weekdays`. A budget caps use inside the window for `.allow` and outside it for `.block`; the second case needs a separate all-day activity per schedule (`outsideWindowActivityName`).

**The NFC tag is the only key.** `TagSecret` keeps a per-install secret's SHA256 hash in the Keychain. A verified scan suspends active schedules, toggles the manual block, and grants profile editing for `profileEditAccessDuration`. Emergency unblocks clear a shield without a scan, capped per month, and deliberately do not grant editing. Anything that would let a profile or schedule change without a scan is a bypass; see the hardening section of `PLAN.md`.

**Logging.** `BrokeLog` writes through `os_log` (subsystem `com.Brokeest.ios`) and mirrors each line into the App Group, which is how the extension's decisions become readable from the app. Use it rather than `NSLog`. The `DEBUG`-only diagnostics screen in `BrockerView.swift` shows those lines plus a live snapshot of every store.

## PLAN.md

`PLAN.md` is the design record for scheduling and hardening, including why each bypass is closed. Update it when behavior it describes changes.
