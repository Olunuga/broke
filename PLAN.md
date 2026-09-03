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
- **A budget means something different per mode.** For `.allow`, it caps usage inside
the usable window — a `DeviceActivityEvent` on the schedule's own activity, with
`threshold: DateComponents(minute: n)`, works directly since the event only needs to
track usage during that same interval. For `.block`, it caps usage outside the blocked
window instead — the block activity's own interval covers the wrong span for that, so
it uses a second, all-day activity per schedule; see phase 5 for why that works without
splitting the budget across two disjoint spans, and how closing the window avoids
wrongly clearing a budget-triggered block.
- **Activity count roughly doubles for a `.block` schedule with a budget set**, since it

registers both the window's own activity and the all-day outside-window tracker —
still well below the `excessiveActivities` limit for a handful of schedules.
- **An App Group carries state** between app and extension: profiles, active profile
ID, and the suspension date.
- **Each schedule owns its own named `ManagedSettingsStore`**, keyed by the
schedule's id. The manual tag-toggle keeps its own separate `"broke"`-named store.
`ManagedSettingsStore` settings from different stores are combined by the system, not
last-write-wins, so a schedule's shield can never stomp the manual toggle's or another
schedule's.
- **Both `intervalDidStart` and `intervalDidEnd` recompute full state from scratch**
rather than assume which edge fired. `DeviceActivitySchedule` has no weekday
parameter — it only fires daily at a fixed start/end time-of-day — so the extension
re-checks `weekdays`, `isEnabled`, and suspension on every callback and applies or
clears the shield accordingly. This is also why a schedule's shield is applied
immediately on save rather than waiting for the next boundary.
- **The NFC tag writes a 30-minute suspension deadline.** The extension and
`ScheduleManager` both check it before applying any schedule's shield; see phase 6.

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

A schedule is "usable" at a given moment when today is one of its `weekdays` and the
current time falls inside `startTime`–`endTime`. `.block` blocks exactly while usable;
`.allow` blocks everywhere else, including days not in `weekdays`.

| Mode     | Blocked when |
| -------- | ------------ |
| `.block` | usable        |
| `.allow` | not usable    |

This is recomputed on every `intervalDidStart`/`intervalDidEnd` callback and applied
immediately when a schedule is saved, so an `.allow` schedule blocks from the moment
it exists, not only after its first boundary.

## Checklist

`you` marks Xcode UI and device steps. Everything else is a file change.

### Phase 0 — current state

- [x] Signing set, app runs on device
- [x] `NDEF` added to `Broke/Broke.entitlements`
- [x] Tag write and scan verified
- [x] Fix the inverted write alert (`Broke/BrockerView.swift:118`)

### Phase 1 — shared foundation

No user-visible change. Confirm blocking still works before continuing.

- [x] **you** Signing &amp; Capabilities &gt; + Capability &gt; App Groups &gt; `group.com.Brokeest.ios`
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
- [x] **you** Pick a website in the picker, confirm Safari shows the shield
- [x] **you** Test the same domain in Chrome. Blocked, and confirms the Shield

  Configuration extension in phase 7 is needed to close the passcode override on
  the block screen.

### Phase 3 — schedule model and UI

Persisted but not yet active.

- [x] New `Broke/Schedule.swift`
- [x] `Profile` gains `schedules`
- [x] `ScheduleListView` and `ScheduleFormView` (weekday toggles, two `.hourAndMinute`

  pickers, budget stepper)
- [x] Form validation: reject intervals under 15 minutes, reject windows that cross

  midnight
- [x] **you** Run, open a profile, add a schedule, confirm it saves and reopens with

  the same values. Try an invalid window (end before start, or under 15 minutes)
  and confirm Save stays disabled with the error shown.

### Phase 4 — monitor extension

Window transitions work at the end of this phase.

- [x] `BrokeMonitor` target: Family Controls and App Group entitlements, team

  `CH4P23R94R`, embedded into the app via a Copy Files build phase, wired as a
  target dependency so it builds before the app. The `.appex` lands in
  `Broke.app/PlugIns` with `NSExtensionPrincipalClass` resolving to
  `BrokeMonitor.DeviceActivityMonitorExtension`.
- [x] **you** Confirmed Signing &amp; Capabilities shows Family Controls and the App

  Group on the `BrokeMonitor` target with no signing errors.
- [x] `BrokeMonitor/DeviceActivityMonitorExtension.swift`: `intervalDidStart` and

  `intervalDidEnd` both call `applyState`, which decodes the schedule from the
  activity name via `SharedStore.schedule(withId:)`, then applies or clears that
  schedule's own named store via `ShieldWriter` based on `isEnabled`, suspension, and
  `schedule.wantsBlock()`.
- [x] `Broke/ScheduleManager.swift`: `sync(profiles:)` stops all monitoring, restarts

  it for every enabled and valid schedule, applies each schedule's resting shield
  state immediately, and clears the named store of any schedule id that disappeared
  since the last sync. Called from `ProfileManager`'s schedule add/update/delete and
  once at app launch in `BrokeApp.init`.
- [x] Shield applied on save for both modes, not only `.allow` &mdash; `ScheduleManager.sync`

  computes `wantsBlock()` for every schedule and applies or clears accordingly, so a
  freshly created `.block` schedule outside its window is correctly left unblocked
  rather than needing a separate code path.
- [x] **you** Confirmed a schedule window triggers the shield on-device

### Phase 5 — budgets

- [x] Form copy is mode-aware: `.allow` reads "Limit use inside window"; `.block` reads

  "Limit use outside window".
- [x] For `.allow`: `ScheduleManager.startMonitoring` attaches a `DeviceActivityEvent`

  to the schedule's own activity when `budgetMinutes` is set — the window and the
  tracked usage cover the same span, so one event suffices. Uses
  `includesPastActivity: true` on iOS 17.4+ so the budget survives a schedule edit
  mid-window (`stopMonitoring`/re-register); falls back to the base initializer below
  that OS version, where a mid-window edit does reset the count.
- [x] For `.block`: `Schedule.outsideWindowActivityName`/`outsideWindowEventName` are a

  second, all-day (`00:00`–`23:59`, repeating) activity per schedule, registered
  alongside the window's own — `DeviceActivitySchedule` can't express two disjoint
  spans (before and after the window) as one interval, so splitting the budget across
  two activities was the alternative, and it can't share one threshold across them.
  The all-day tracker works without splitting: the profile is already shielded during
  the window, so no usage accrues there, leaving the count an accurate measure of
  outside-window use alone. Registers daily regardless of `weekdays`, same
  no-weekday-parameter constraint as everywhere else — the extension checks
  `isActiveToday()` before treating a threshold hit as real.
- [x] Closing the window doesn't wrongly clear a budget-triggered block:

  `Schedule.effectiveWantsBlock()` adds "was the outside-window budget already
  exceeded today" on top of `wantsBlock()`, backed by
  `SharedStore.isOutsideWindowBudgetExceeded(for:)` — a flag `eventDidReachThreshold`
  sets, and the tracking activity's own midnight `intervalDidStart` clears, matching
  when its threshold counter itself resets. `ScheduleManager.sync`'s resting-state
  loop and the extension's `apply()` both switched from `wantsBlock()` to
  `effectiveWantsBlock()`, so app-side and extension-side agree.
- [x] `eventDidReachThreshold` applies the schedule's shield once a budget event fires

  — the window's own event clears at its next `intervalDidStart` (a new day resets
  the threshold too); the outside-window event clears the same way via the flag above.
- [ ] **you** Test the Wednesday-to-Saturday, 30-minute `.allow` case
- [ ] **you** Test a `.block` schedule with an outside-window budget: use up the budget

  before the window opens, confirm it blocks through the window and stays blocked
  after the window closes, then confirm it clears at the next day's window start.

### Phase 6 — NFC early unblock

The home screen tracks two independent shield sources: the manual toggle
(`appBlocker.isBlocking`) and any currently active schedule
(`SharedStore.activeBlockingSchedules()`). It shows blocked if either one is, names
which source is active ("Blocked manually", "Blocked by schedule: <name>", or both),
lists each active schedule's window and (for `.allow`) its daily limit, and the tap
label says which action a tap will take.

`SharedStore` is `UserDefaults`-backed and never pushes updates to an already-running
view, so schedule state is refreshed on appear, on returning to the foreground, and on
a 5-second timer while the screen is open — otherwise a schedule starting mid-session
would never show up without backgrounding the app first. A tag scan re-checks
`SharedStore.activeBlockingScheduleNames()` fresh rather than trusting that polled
state, since taking the wrong branch there means touching the wrong shield.

A tag scan while a schedule is the active blocker does not touch the manual toggle —
it suspends every schedule for 30 minutes (`ScheduleManager.suspendActiveSchedules`),
which writes `SharedStore.suspendedUntil` and immediately clears the currently-blocking
schedules' shields via `sync`. A tag scan while nothing is schedule-blocking falls
through to the pre-existing manual toggle, unchanged.

The manual toggle and each schedule write to separate named `ManagedSettingsStore`s
(see Design). `appBlocker.toggleBlocking` is only reachable when no schedule is
blocking (see below), so there's no UI path where it runs during an active schedule
block to interfere with.

Since a schedule's own start/end boundaries are typically hours apart, nothing else
fires at the 30-minute mark on its own. `ScheduleManager` registers a one-shot,
non-repeating `DeviceActivitySchedule` ending exactly at `suspendedUntil`
(`SharedStore.resumeCheckActivityName`, minute precision — `DeviceActivitySchedule`'s
documented pattern centers on hour/minute, and second-level components risked a silent
`invalidDateComponents` failure with no way to observe it from the UI); its
`intervalDidEnd` re-evaluates every known schedule and re-applies whichever ones
`wantsBlock()` again. `sync` re-registers this wake-up on every call while a
suspension is in progress, so an unrelated schedule edit
made during the 30 minutes doesn't cancel the automatic re-block.

- [x] Home screen reflects schedule-driven blocking, not just the manual toggle
- [x] Tag scan during a scheduled block suspends for 30 minutes and clears the shield
- [x] A one-shot wake-up activity re-applies the shield automatically when the

  suspension ends
- [x] Schedule state refreshes on a 5-second timer while the screen is open, not only

  on appear/foreground, and a tag scan re-checks fresh state rather than the polled
  `@State` before deciding which shield to touch
- [x] **you** Confirmed on-device: triggering a schedule, scanning the tag, and

  clearing the suspension early all behave correctly — the block clears on suspend and
  reapplies immediately once the suspension ends, label changes throughout.
- [x] **you** Confirmed the unassisted wake-up on-device: with a 16-minute suspension

  and Broke backgrounded, the shield reapplied itself mid-use at expiry, with no app
  launch or foreground resync involved.
- [ ] **you** Untested: suspensions shorter than `DeviceActivityCenter`'s 15-minute

  minimum. `scheduleWakeUp` clamps `intervalStart` backwards to satisfy that minimum
  when the suspension is shorter, which places the start in the past — whether iOS
  accepts a past start for a non-repeating schedule is unconfirmed. Any test at or
  above 15 minutes takes the natural path and leaves this clamp unexercised.
- [x] The manual toggle can't touch a schedule's shield through the UI: `scanTag`

  checks `SharedStore.activeBlockingSchedules()` before deciding what a tap does,
  and takes the suspend branch whenever a schedule is active — `appBlocker.toggleBlocking`
  is only reachable when no schedule is blocking, so there's no user-reachable path
  where a manual toggle runs during an active schedule block.

### Phase 7 — hardening

- [ ] **you** Set a Screen Time passcode you do not know yourself (Settings &gt; Screen

  Time &gt; Use Screen Time Passcode). Every item below, and every restriction Broke
  sets through `ManagedSettings`, is gated by this passcode. Without it, Settings &gt;
  Screen Time &gt; Broke lets you revoke authorization or undo any restriction with no
  barrier at all.
- [x] Two more extension targets, `BrokeShieldConfig` and `BrokeShieldAction`, match

  the extension point identifiers and protocol signatures in Apple's own Xcode
  templates (`Shield Configuration Extension.xctemplate` / `Shield Action
  Extension.xctemplate`). The two work together; neither alone closes the gap.
  `BrokeShieldConfig` (`ShieldConfigurationDataSource`, all four
  `configuration(shielding:)` overrides) replaces the default block screen's
  appearance and omits `secondaryButtonLabel` entirely — that's where the built-in
  "unlock with Screen Time passcode" option lives. `BrokeShieldAction`
  (`ShieldActionDelegate`) handles what the remaining button does: `.close` on every
  case, which dismisses the shield UI without touching the underlying
  `ManagedSettingsStore`. Neither `ShieldActionResponse` case can trigger a passcode
  prompt, so together these fully replace it — the Broke tag, scanned in the app, is
  the only way through. Applies to both apps and websites, and with or without the
  Screen Time passcode item above.
- [x] New `HardeningManager`, dual-target like `Schedule`/`SharedStore`/`ShieldWriter`.

  `refresh()` reads `SharedStore.isAnythingBlocking` (manual toggle or any schedule)
  and sets or clears `denyAppRemoval`, `requireAutomaticDateAndTime`, `lockAccounts`,
  `lockPasscode`, and `denySiri` together on a dedicated `"broke-hardening"` named
  store — active exactly while something is blocking, off otherwise. Called from
  `AppBlocker.applyBlockingSettings`, `ScheduleManager.sync`, and all three of the
  extension's callbacks, so every path that can change what's blocking keeps it in
  sync.
- [x] `store.webContent.blockedByFilter` as an opt-in per-profile allowlist —

  `Profile.restrictWebToAllowlist`. When on, the profile's existing `webDomainTokens`
  switch meaning from "these are blocked" to "only these are reachable, block
  everything else" (`.all(except:)`); when off, unchanged deny-list behavior.
  Toggle lives in `ProfileFormView` next to the website configuration.
- [ ] **you** Test both: with a schedule active, confirm Settings > Screen Time shows

  the app-removal/passcode/accounts/date-time/Siri restrictions active, and gone once
  nothing is blocking. Turn on the web allowlist for a profile with one or two sites
  selected, block it, and confirm only those sites load.
- [x] Editing any profile setting (schedules included) while blocking is active — this

  was largely already true by construction: `ProfilesPicker`, the only path to
  `ProfileFormView` → `ScheduleListView` → `ScheduleFormView`, only renders when
  `!isBlocked` in `BrokerView`, and the only way to clear `isBlocked` while a schedule
  is active is a tag scan. The remaining gap was a sheet already open when a schedule
  triggers mid-edit: `ProfileFormView` now polls `SharedStore.isAnythingBlocking` every
  5 seconds and on appear, dismissing itself immediately if blocking starts while
  presented — explicit, rather than relying on the sheet being torn down implicitly
  when `ProfilesPicker` leaves the view tree.
- [x] The "+" create-tag button is hidden, not just disabled, while anything is

  blocking. Left visible, it would let anyone with a blank NFC tag mint a new valid
  one on the spot, making the physical-tag requirement meaningless.
- [x] **you** Confirmed on-device: the custom Broke shield shows for a blocked app,

  with one button only and no passcode-override path. Same result for a blocked
  website in Safari.
- [ ] Replace the fixed tag phrase (`Broke/BrockerView.swift:17`) with a random

  per-install secret. Store its hash in the Keychain and write the secret to the tag.
- [ ] **you** Re-write the existing tag, because the old phrase stops working

### Deferred

- [ ] `.child` authorization in place of `.individual`. It is the only way to stop

  revocation in Settings &gt; Screen Time, and it needs Family Sharing with a second
  Apple ID.

## Limits

- Every restriction Broke sets through `ManagedSettings` is only as strong as the
device's Screen Time passcode. With no passcode set, Settings &gt; Screen Time &gt; Broke
lets any restriction be undone with no barrier, and Screen Time override prompts
(such as a blocked website's) let content through unchecked.
- `denyAppRemoval` stops deletion of every app on the device, not only Broke.
- `.individual` authorization stays revocable in Settings &gt; Screen Time, passcode
permitting.
- Extension callbacks arrive within a few minutes of the boundary, not at the exact
second. A 30-minute budget can overrun slightly.
- `DeviceActivityCenter` rejects intervals under 15 minutes with `intervalTooShort`.
- A window that crosses midnight must be split into two schedules.
- Extension callbacks do not fire in the simulator.

