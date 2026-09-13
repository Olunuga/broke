# Scheduling and hardening plan

Adds time-based blocking to Broke, extends blocking to websites, and closes the
bypasses that iOS allows an app to close.

Bundle ID `com.Brokeest.ios`, team `CH4P23R94R`, App Group `group.com.Brokeest.ios`.

## Design

A `DeviceActivityMonitor` app extension applies and removes the shield while the
main app is not running. The app alone cannot do this.

- **One `DeviceActivityName` per window**, named by the window's id, with a daily
repeating interval. `DeviceActivitySchedule` cannot express several disjoint spans as
one interval, so a schedule with two windows registers two activities. The extension
filters by weekday inside `intervalDidStart`.
- **One all-day budget activity per schedule with a daily limit**, named
`"<scheduleId>-budget"`, in both modes. Usage only accrues while the profile is
unshielded, which is exactly the span each mode's limit caps: under `.block` the time
outside every window, under `.allow` the time inside them. All-day rather than
per-window, so one limit covers the whole day however many windows there are, and
`weekdays` is checked when the threshold fires rather than by the interval.
- **Activity count is windows plus one per schedule with a limit** — well below the
`excessiveActivities` limit for a handful of schedules.
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

struct ScheduleWindow: Codable, Identifiable {
    let id: UUID
    var startTime: DateComponents   // hour, minute
    var endTime: DateComponents
}

struct Schedule: Codable, Identifiable {
    let id: UUID
    var name: String
    var mode: ScheduleMode
    var weekdays: Set<Int>          // Calendar convention: 1 = Sunday
    var windows: [ScheduleWindow]
    var budgetMinutes: Int?         // nil = no limit
    var isEnabled: Bool
}
```

A window may not cross midnight, and `weekdays` means the day a window starts on. An
overnight span is two windows, 22:00-23:59 and 00:00-06:00, in the same schedule.
Windows may not overlap each other, and each must be at least
`minimumDurationMinutes` long.

`Profile` gains `schedules: [Schedule]` and `webDomainTokens: Set<WebDomainToken>`.
`Profile` and `Schedule` both need a custom `init(from:)` so records saved by earlier
versions still decode; a schedule stored with `startTime`/`endTime` and no `windows`
decodes to a single window.

Example: usable Wednesday to Saturday, 30 minutes maximum. One schedule, mode
`.allow`, weekdays `{4,5,6,7}`, one window 00:00-23:59, limit 30.

Example: an early-morning and an evening block. One schedule, mode `.block`, windows
06:00-08:00 and 20:00-22:00.

### Mode behaviour

A schedule is "usable" at a given moment when today is one of its `weekdays` and the
current time falls inside any of its windows. `.block` blocks exactly while usable;
`.allow` blocks everywhere else, including days not in `weekdays`.

Windows belong to one schedule rather than to separate schedules because shields
compose by union: two `.allow` schedules would each block the other's window, leaving
the profile blocked all day, and two schedules carry two independent daily limits.

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
- [x] `Schedule.budgetActivityName`/`budgetEventName` are one all-day

  (`00:00`-`23:59`, repeating) activity per schedule, registered by
  `ScheduleManager.startBudgetMonitoring` whenever `budgetMinutes` is set, in both
  modes. A window's own interval covers the wrong span for a limit, and a schedule may
  hold several windows, so a per-window event would either split one limit across them
  or hand out the limit once per window. The all-day tracker needs neither: the profile
  is shielded outside the usable spans, so no usage accrues there, leaving the count an
  accurate measure of exactly what each mode caps. Uses `includesPastActivity: true` on
  iOS 17.4+ so the count survives a schedule edit (`stopMonitoring`/re-register); below
  that OS version an edit resets it. Registers daily regardless of `weekdays`, the same
  no-weekday-parameter constraint as everywhere else, so the extension checks
  `isActiveToday()` before treating a threshold hit as real.
- [x] A window boundary doesn't wrongly clear a limit-triggered block:

  `Schedule.effectiveWantsBlock()` adds "was the limit already spent today" on top of
  `wantsBlock()`, backed by `SharedStore.isBudgetSpent(for:)` — a date-stamped flag
  `eventDidReachThreshold` sets, and which expires on its own at midnight rather than
  depending on a callback to clear it. `ScheduleManager.sync`'s resting-state loop and
  the extension's `apply()` both use `effectiveWantsBlock()`, so app-side and
  extension-side agree.
- [x] `eventDidReachThreshold` sets the flag and applies the schedule's shield, for both

  modes, behind the `isActiveToday()` guard.
- [ ] **you** Test the Wednesday-to-Saturday, 30-minute `.allow` case
- [ ] **you** Test a `.block` schedule with a daily limit: use up the limit before the

  window opens, confirm it blocks through the window and stays blocked after the window
  closes, then confirm it clears the next day.
- [ ] **you** Test a `.allow` schedule with a morning and an evening window: confirm the

  profile is usable in both and blocked between them, then spend the limit in the
  morning window and confirm the evening window stays blocked until the next day.

### Phase 6 — NFC early unblock

The home screen tracks two independent shield sources: the manual toggle
(`appBlocker.isBlocking`) and any currently active schedule
(`SharedStore.activeBlockingSchedules()`). It shows blocked if either one is, names
which source is active ("Blocked manually", "Blocked by schedule: <name>", or both),
lists each active schedule's window and (for `.allow`) its daily limit, and the tap
label says which action a tap will take.

`SharedStore` is `UserDefaults`-backed and never pushes updates to an already-running
view, so schedule state is refreshed on appear, on returning to the foreground, and on
a 1-second timer while the screen is open — otherwise a schedule starting mid-session
would never show up without backgrounding the app first. A tag scan re-checks
`SharedStore.activeBlockingSchedules()` fresh rather than trusting that polled
state, since taking the wrong branch there means touching the wrong shield.

A tag scan while a schedule is the active blocker does not touch the manual toggle —
it suspends every schedule for `SharedStore.suspensionDuration` (30 minutes) via
`ScheduleManager.suspendActiveSchedules`, which writes `SharedStore.suspendedUntil` and
immediately clears the currently-blocking schedules' shields through `sync`. A tag scan
while nothing is schedule-blocking falls through to the pre-existing manual toggle,
unchanged.

Five 15-minute emergency unblocks per calendar month are available without a tag, from
a button on the blocked screen showing how many remain
(`ScheduleManager.useEmergencyUnblock`), behind a confirmation naming how many will be
left. The tag carries physical friction — it has to be to hand — so these cover when it
isn't, and the cap keeps them an exception rather than a way around it. The count is
derived from a stored date rather than reset by a callback, so nothing has to fire at
the month boundary for the allowance to refill.

An emergency unblock suspends every schedule, not one: `suspendedUntil` is a single
value, so the button cannot be conditioned per schedule. With two schedules blocking for
different reasons, one unblock lifts both. Per-schedule suspension is the change that
would fix that.

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
- [x] Schedule state refreshes on a 1-second timer while the screen is open, not only

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

- [x] **you** Set a Screen Time passcode you do not know yourself (Settings &gt; Screen

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
  and `lockPasscode` together on a dedicated `"broke-hardening"` named store — active
  exactly while something is blocking, off otherwise. Called from
  `AppBlocker.applyBlockingSettings`, `ScheduleManager.sync`, and all three of the
  extension's callbacks, so every path that can change what's blocking keeps it in
  sync.
- [x] `store.webContent.blockedByFilter` as an opt-in per-profile allowlist —

  `Profile.restrictWebToAllowlist`. When on, the profile's existing `webDomainTokens`
  switch meaning from "these are blocked" to "only these are reachable, block
  everything else" (`.all(except:)`); when off, unchanged deny-list behavior.
  Toggle lives in `ProfileFormView` next to the website configuration.
- [ ] **you** Test both: with a schedule active, confirm Settings > Screen Time shows

  the app-removal/passcode/accounts/date-time restrictions active, and gone once
  nothing is blocking. Turn on the web allowlist for a profile with one or two sites
  selected, block it, and confirm only those sites load.
- [x] Editing any profile setting (schedules included) without a tag scan.

  A tag scan is the only thing that opens `ProfileFormView` → `ScheduleListView` →
  `ScheduleFormView`. `SharedStore.grantProfileEditAccess()` runs on every verified
  scan and unlocks editing for `profileEditAccessDuration` (10 minutes);
  `isProfileEditingUnlocked` also reads false whenever anything is blocking. While
  locked, `ProfilesPicker` still lists profiles and still switches the active one, but
  the long-press edit and the "New..." cell start a scan instead, and the footer is a
  "Scan tag to edit profiles" button. Editing stays open until the first tag is
  registered, since there is nothing to scan before that.

  The grant is revoked when a block starts (the home screen's 1-second refresh) and
  when the app goes to the background, so neither an emergency unblock nor a schedule
  ending hands back an unlock the tag was never scanned for. A sheet already open when
  a schedule triggers mid-edit is covered separately: `ProfileFormView` polls
  `SharedStore.isAnythingBlocking` every 5 seconds and on appear, dismissing itself
  rather than relying on the sheet being torn down implicitly when `ProfilesPicker`
  leaves the view tree.
- [x] The daily limit is one all-day activity per schedule, in both modes.

  `SharedStore.isBudgetSpent`/`setBudgetSpent` hold a date stamp rather than a bare
  flag, checked against "is that date today", so the limit refills at midnight without
  any callback having to fire. `effectiveWantsBlock` layers it on top of `wantsBlock`
  for both modes, which is what stops a window boundary from clearing a block the
  limit is still enforcing. The extension checks `isActiveToday()` before enforcing a
  threshold hit, since the tracker runs daily regardless of `weekdays`.
- [x] Three injection points exist for tests, and nothing in the app writes to any of them.

  `SharedStore.defaults` is a `var` so a test can point it at a scratch `UserDefaults`
  suite instead of the App Group. `ScheduleManager.center` and
  `ScheduleManager.shieldTarget` are `var`s so a test can observe which activities `sync`
  registers and which store it shields or clears. All three are internal to the app
  module, so only `@testable import Broke` reaches them, and each has a production
  default that the app never replaces.
- [x] Profile import is gated the same way profile creation is.

  `ProfilesPicker`'s import button starts a scan instead of the file picker while
  editing is locked, and `handleImport` re-checks the grant before writing anything —
  the file picker takes long enough that a block can start while it is open. Export is
  ungated: it reads profiles and changes nothing that is enforced.
- [x] The "+" create-tag button is gated on `!TagSecret.isRegistered || !isBlocked`,

  not on `isBlocked` alone. A schedule starts without a tag scan, so gating on
  `isBlocked` alone means a schedule beginning before any tag exists leaves no way to
  create the only thing that can suspend it. Until a tag is registered the button
  stays available even while blocked; once one exists, writing another mid-block would
  be a way around the physical tag, so it hides until blocking ends.
- [x] **you** Confirmed on-device: the custom Broke shield shows for a blocked app,

  with one button only and no passcode-override path. Same result for a blocked
  website in Safari.
- [x] `TagSecret` replaces the fixed tag phrase with a 32-byte random per-install

  secret. Only its SHA256 hash is kept, in the Keychain
  (`kSecAttrAccessibleAfterFirstUnlock`), so reading the stored value back off the
  device yields nothing writable to a tag. Registration is recorded separately, and
  only once the NFC write reports success — gating the create-tag button on hash
  presence instead would hide it after a failed write, with a hash stored, no tag
  carrying it, and no way to retry.
- [x] **you** Wrote a tag carrying a per-install secret. The old fixed-phrase tag no

  longer works.

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
- A window that crosses midnight must be split into two windows.
- Extension callbacks do not fire in the simulator.
- `ApplicationToken`, `ActivityCategoryToken`, and `WebDomainToken` are opaque values
the system issues per install. An exported profile carries them, but they only resolve
on the install that wrote the file, so an import elsewhere keeps the name, icon, and
schedules and drops the selections.

