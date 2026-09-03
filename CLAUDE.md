# Working in this repo

iOS app that blocks apps and websites on a schedule, unlocked by scanning an NFC tag.
Built on `FamilyControls` / `ManagedSettings` / `DeviceActivity`.

`PLAN.md` holds the feature design, the reasoning behind each mechanism, and the
checklist of what is built versus still unverified. Read it before changing scheduling,
budgets, or hardening — several decisions there look arbitrary without the constraint
that forced them.

## Targets

| Target | Role |
|---|---|
| `Broke` | The app |
| `BrokeMonitor` | `DeviceActivityMonitor` — applies and removes shields while the app isn't running |
| `BrokeShieldConfig` | `ShieldConfigurationDataSource` — replaces the system block screen |
| `BrokeShieldAction` | `ShieldActionDelegate` — handles that screen's button |

`Schedule.swift`, `SharedStore.swift`, `ShieldWriter.swift`, `Profile.swift`, and
`HardeningManager.swift` are compiled into **both** `Broke` and `BrokeMonitor`. The app
and the extension both need to evaluate the same rules, so any change to blocking logic
has to hold for both.

## The project file is hand-maintained

`project.pbxproj` predates file-system-synchronized groups. A `.swift` file on disk is
**not** in the build until it is registered in four places:

1. `PBXBuildFile` entry
2. `PBXFileReference` entry
3. The group's `children` list
4. The target's `PBXSourcesBuildPhase` files list

For a file shared with `BrokeMonitor`, add a second `PBXBuildFile` (same `fileRef`, new
id) and list it in that target's sources phase too.

Editing the pbxproj by script is workable — anchor on a unique existing line, assert it
appears exactly once, insert relative to it. Validate afterwards:

```sh
plutil -convert xml1 -o - Broke.xcodeproj/project.pbxproj > /dev/null   # syntax
xcodebuild -list -project Broke.xcodeproj                                # targets/schemes
```

After adding a target, Xcode's scheme selector may switch to it or drop `Broke` from
the list. Quit Xcode, delete
`Broke.xcodeproj/xcuserdata/<user>.xcuserdatad/xcschemes/xcschememanagement.plist`, and
reopen — that file is a local cache and is regenerated. If a run prompts "Choose an app
to run", the active scheme is an extension; switch it back to `Broke`.

## Verifying a change

```sh
xcodebuild -project Broke.xcodeproj -scheme Broke \
  -destination 'generic/platform=iOS' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

This is the ground truth. Build `-configuration Release` as well when touching anything
inside `#if DEBUG`, since that is the configuration where such code is stripped.

**Ignore SourceKit diagnostics claiming `'X' is unavailable in macOS` or
`Cannot find 'SharedStore' in scope`.** The editor indexes against macOS, where
`ManagedSettings` and `DeviceActivity` don't exist, and doesn't resolve cross-file
symbols in this project. These appear constantly and are almost always noise. Trust
`xcodebuild`.

To confirm a file compiled into both targets, count its compile lines — two means both:

```sh
grep -c "Compiling SharedStore.swift" build.log
```

## Testing constraints

- **`DeviceActivity` callbacks never fire in the simulator.** Scheduling, budgets, and
  the shield screens can only be tested on a physical device.
- **`DeviceActivityCenter` rejects intervals under 15 minutes** (`intervalTooShort`).
  The error only reaches `NSLog`, so a schedule silently fails to register. Watch for
  this whenever a duration becomes configurable.
- **Extension callbacks are not instant.** They arrive within minutes of a boundary,
  and a callback queued while the app was suspended may be delivered on resume. Display
  code that reads shared state immediately at launch or resume can catch a stale value;
  the app polls once a second so the correction reads as instant.
- **The device's Screen Time passcode is deliberately not known to the developer.**
  Restrictions applied through `ManagedSettings` cannot be undone without it.

## Setting up a fresh clone

Signing values are committed (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, App
Group `group.com.Brokeest.ios`). A different developer must replace all three, in
`project.pbxproj`, `SharedStore.appGroupID`, and the three `.entitlements` files.

In Xcode, confirm under Signing & Capabilities:

- `Broke` — App Groups, Family Controls, Near Field Communication Tag Reading
- `BrokeMonitor`, `BrokeShieldConfig`, `BrokeShieldAction` — Family Controls

A paid Apple Developer Program membership is required; Family Controls and NFC are not
available to free personal teams.
