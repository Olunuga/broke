# Scheduling and hardening plan

Adds time-based blocking to Broke, extends blocking to websites, and closes the
bypasses that iOS allows an app to close.

Bundle ID `com.Brokeest.ios`, team `CH4P23R94R`, App Group `group.com.Brokeest.ios`.

## Design

A `DeviceActivityMonitor` app extension applies and removes the shield while the
main app is not running. The app alone cannot do this.

- **One `DeviceActivityName` per schedule**, with a daily repeating interval. The
  extension filters by weekday inside `intervalDidStart`. Activity count equals the
  number of schedules, which stays well below the `excessiveActivities` limit.
- **A budget is a `DeviceActivityEvent`** on the same activity, with
  `threshold: DateComponents(minute: n)`. Thresholds reset at each interval start, so
  a daily interval gives a per-day budget.
- **An App Group carries state** between app and extension: profiles, active profile
  ID, and the suspension date. The shield uses `ManagedSettingsStore(named: "broke")`
  so both processes write the same store.
- **The NFC tag writes a suspension date** of the next midnight. The extension reads
  it before it applies any shield.

### Data model

```swift
enum ScheduleMode: String, Codable { case block, allow }

struct Schedule: Codable, Identifiable {
    let id: UUID
    var name: String
    var mode: ScheduleMode
    var weekdays: Set<Int>          // Calendar convention: 1 = Sunday
    var startTime: DateComponents   // hour, minute
    var endTime: DateComponents
    var budgetMinutes: Int?         // nil = no budget
    var isEnabled: Bool
}
```

`Profile` gains `schedules: [Schedule]` and `webDomainTokens: Set<WebDomainToken>`.
Both need a custom `init(from:)` so profiles saved by earlier versions still decode.

Example: usable Wednesday to Saturday, 30 minutes maximum. One schedule, mode
`.allow`, weekdays `{4,5,6,7}`, window 00:00-23:59, budget 30.

### Mode behaviour

| Mode | `intervalDidStart` | `eventDidReachThreshold` | `intervalDidEnd` |
|---|---|---|---|
| `.block` | apply shield | - | remove shield |
| `.allow` | remove shield | apply shield | apply shield |

An `.allow` schedule also needs the shield applied when the schedule is saved, so
that time outside the window is blocked from the start.

Set `includesPastActivity: true` on the event. Without it a budget restarts if
monitoring re-registers mid-window.

## Checklist

`you` marks Xcode UI and device steps. Everything else is a file change.

### Phase 0 — current state

- [x] Signing set, app runs on device
- [x] `NDEF` added to `Broke/Broke.entitlements`
- [x] Tag write and scan verified
- [x] Fix the inverted write alert (`Broke/BrockerView.swift:118`)

### Phase 1 — shared foundation

No user-visible change. Confirm blocking still works before continuing.

- [x] **you** Signing & Capabilities > + Capability > App Groups > `group.com.Brokeest.ios`
- [x] Add `com.apple.security.application-groups` to `Broke/Broke.entitlements`
- [x] New `Broke/SharedStore.swift`: group `UserDefaults`, named `ManagedSettingsStore`,
      suspension date, one-time migration from `UserDefaults.standard`
- [x] `ProfileManager` reads and writes the group defaults
- [x] `AppBlocker` uses the named store; `BrokeApp.init` runs the migration first
- [x] **you** Run, confirm existing profiles survive and blocking still works

### Phase 2 — websites

- [x] `Profile` gains `webDomainTokens`
- [x] `ProfileFormView` reads and writes `activitySelection.webDomainTokens`
- [x] `AppBlocker` sets and clears `store.shield.webDomains`
- [ ] **you** Pick a website in the picker, confirm Safari shows the shield
- [ ] **you** Test the same domain in Chrome, and record the result. It decides whether
      the phase 7 allowlist is needed.

### Phase 3 — schedule model and UI

Persisted but not yet active.

- [ ] New `Broke/Schedule.swift`
- [ ] `Profile` gains `schedules`
- [ ] `ScheduleListView` and `ScheduleFormView` (weekday toggles, two `.hourAndMinute`
      pickers, budget stepper)
- [ ] Form validation: reject intervals under 15 minutes, reject windows that cross
      midnight

### Phase 4 — monitor extension

Window transitions work at the end of this phase.

- [ ] **you** File > New > Target > Device Activity Monitor Extension, named `BrokeMonitor`
- [ ] **you** Give the extension the Family Controls capability, the App Group, and the team
- [ ] `BrokeMonitor/DeviceActivityMonitorExtension.swift`: `intervalDidStart`,
      `intervalDidEnd`, weekday filter, suspension check
- [ ] `Broke/ScheduleManager.swift`: `startMonitoring` and `stopMonitoring`
- [ ] Apply the shield on save for `.allow` schedules
- [ ] **you** Set a window a few minutes ahead, confirm the shield appears and clears

### Phase 5 — budgets

- [ ] Attach `DeviceActivityEvent(applications:categories:webDomains:threshold:includesPastActivity:)`
- [ ] Handle `eventDidReachThreshold` by applying the shield
- [ ] **you** Test the Wednesday-to-Saturday, 30-minute case

### Phase 6 — NFC suspension until midnight

- [ ] A tag scan during a scheduled block writes `suspendedUntil = startOfDay(tomorrow)`
      and clears the shield
- [ ] The extension skips applying a shield while `Date() < suspendedUntil`
- [ ] A second scan clears the date and re-applies the shield, keeping the tag a toggle
- [ ] Main screen shows the suspension state and the next transition time

### Phase 7 — hardening

- [ ] `store.application.denyAppRemoval = true`
- [ ] `store.dateAndTime.requireAutomaticDateAndTime = true`
- [ ] `store.account.lockAccounts = true` and `store.passcode.lockPasscode = true`
- [ ] `store.siri.denySiri = true`
- [ ] `store.webContent.blockedByFilter = .all(except:)` as an opt-in allowlist per profile
- [ ] Require a tag scan before a schedule is edited or deleted while blocking is active
- [ ] Replace the fixed tag phrase (`Broke/BrockerView.swift:17`) with a random
      per-install secret. Store its hash in the Keychain and write the secret to the tag.
- [ ] **you** Re-write the existing tag, because the old phrase stops working

### Deferred

- [ ] Shield Configuration extension for a custom block message
- [ ] `.child` authorization in place of `.individual`. It is the only way to stop
      revocation in Settings > Screen Time, and it needs Family Sharing with a second
      Apple ID.

## Limits

- `denyAppRemoval` stops deletion of every app on the device, not only Broke.
- `.individual` authorization stays revocable in Settings > Screen Time.
- Extension callbacks arrive within a few minutes of the boundary, not at the exact
  second. A 30-minute budget can overrun slightly.
- `DeviceActivityCenter` rejects intervals under 15 minutes with `intervalTooShort`.
- A window that crosses midnight must be split into two schedules.
- Extension callbacks do not fire in the simulator.
