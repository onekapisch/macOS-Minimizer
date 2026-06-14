# Minimizer Engineering Notes

Read this before touching the minimize/restore engine. These decisions came from real
testing and should not be re-litigated without new evidence.

## Current Engine — HIDE (snappy, no cascade)

Minimizer hides apps via `NSRunningApplication.hide()` / `.unhide()` (see
`AppDelegate.hideAll/unhideAll/applyHidden`). Hide has NO per-window animation, so
windows vanish "all at once" — the snappy feel users expect.

WHY NOT minimize-to-Dock: the genie "one-by-one" cascade is UNAVOIDABLE for
minimize-to-Dock and cannot be removed without disabling SIP. Confirmed by:
- BetterTouchTool dev: bypassing the minimize animation is "impossible without
  disabling SIP"; Apple locked private windowing APIs in Sonoma+.
  https://community.folivora.ai/t/minimize-windows-without-animation/34266
- yabai needs partial-SIP-disable + a Dock scripting addition for deep window control.
  https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
SIP-disable is a non-starter for a shipped app, so HIDE is the only path to instant.

RELIABILITY (the part that was missing before): hide()/unhide() are best-effort and
only take effect on the NEXT run-loop turn. So a tight loop drops most. FIX = fire all,
then on a later run-loop turn VERIFY `isHidden` and RETRY stragglers (up to 6× ~50ms
apart). This makes "hide everything" reliable. Do NOT remove the verify+retry.

RESTORE: unhide the same apps (hide/unhide never reorders → z-order preserved, which
also fixes the old restore-focus bug), then focus the originally-frontmost app via AX
`kAXFrontmost` + `activate()` (twice, 0.12s/0.30s). Accessibility is still required —
for that reliable focus restore.

TRADE-OFF (accepted): hidden windows don't appear as Dock thumbnails.

FINDER: MEASURED via on-screen testing + log. `NSRunningApplication.hide()` returns
false for Finder ("a type that cannot be hidden") AND — critically — `hide()`'s return
value is UNRELIABLE for ALL apps (it returned false even for Notes/Calculator, which it
DOES hide). So do NOT branch on the return value. CORRECT FIX (verified working):
  - hide() EVERY app whose bundleId is NOT in `cannotHide` (currently {com.apple.finder}).
  - For Finder (cannotHide), AX-minimize its windows (axVisibleWindows + setWindowsMinimized),
    tracked in `minimizedFallbackWindows`, un-minimized on restore.
  - Verify+retry BOTH paths: applyHidden (hide group) and minimizeRetry (AX windows) —
    one Finder window typically needs a retry to actually minimize.
VERIFIED by driving the app via computer-use: 6+ minimize cycles → fully clean desktop
every time (Finder included). Restore returns all windows; focus the originally-active
app via kAXFrontmost + AXRaise of its focused window at 0.2/0.6/1.2s (the late one beats
Finder's un-minimize raising itself). Confirmed: active app's window ends on top.

## Rejected Engines

- Minimize-to-Dock via `AXMinimized`: reliable, but the per-window genie cascade is
  macOS-imposed and looks "one by one" — the exact thing users frowned on. Cannot be
  synchronized/instant without SIP (see above). Replaced by HIDE.
- `NSApplication.hideOtherApplications(nil)`: no-op from an LSUIElement menu-bar agent.
- Mission Control "Show Desktop" via CoreDock / Darwin notification: CoreDock was
  REMOVED in macOS 26; the notification is ignored.
- Mission Control "Show Desktop" through CoreDock or Darwin notifications: not a
  supported path for this app. CoreDock was removed on macOS 26, and the notification
  path is not reliable enough for this product.

Do not reintroduce these engines.

## AXMinimized Implementation Rules

- Capture every window whose `kAXMinimizedAttribute` is not definitely `true`.
- Do not use `CGWindowList` visibility to decide whether a window should be included.
  Use the CG window id only for front-to-back ranking.
- Fire AX commands in a wide concurrent burst, but keep the overall minimize/restore
  cycle serialized on `axQueue`.
- Keep the verify-and-retry minimize pass for stragglers.
- Panels, sheets, and utility windows that cannot minimize are expected to be skipped.

## Restore Focus

Capture the frontmost app pid and its `kAXFocusedWindow` at minimize time.

Default restore behavior:

1. Un-minimize background windows first.
2. Poll until those windows no longer report `kAXMinimized == true` and remain
   stable briefly, with a bounded timeout.
3. Un-minimize the originally focused window last.
4. Focus the originally active window once through AX: set the app `kAXFrontmost`,
   set the app focused window,
   perform `kAXRaise`, and set `kAXMain`.

Do not use repeated delayed focus assertions. They create a visible focus bounce when
slow apps finish un-minimizing after the target app has already been refocused.
`NSRunningApplication.activate()` alone is unreliable from a background agent due to
macOS focus-stealing prevention.

This prioritizes correct focus over the appearance of perfect visual simultaneity.
macOS controls the visible window animation timing.

## macOS-Controlled Behavior

The minimize-to-Dock genie animation timing is controlled by macOS and by the target
apps. Minimizer can dispatch commands quickly, but it cannot make every app's genie
animation finish in the same frame. User-side settings that change the visible effect:
System Settings -> Accessibility -> Display -> Reduce Motion, or Desktop & Dock ->
Minimize using Scale.

## App Nap

Keep both App Nap protections:

- Lifetime `ProcessInfo.processInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep, ...)`
  token stored on `AppDelegate`.
- `NSAppSleepDisabled = true` in `Resources/Info.plist`.

These prevent the menu-bar agent from becoming sluggish after idle.

## Testing

Always test one signed Release app instance:

```sh
swift build -c release && ./build_app.sh
for p in $(pgrep -f "MacOS/Minimizer"); do kill -9 "$p"; done
open "Minimizer.app"
pgrep -lf "MacOS/Minimizer"
```

`pgrep` should show exactly one Minimizer runtime process. Do not run the Xcode Debug
build and the Release app at the same time; they fight over the global hotkey.

## XcodeGen

SwiftPM auto-includes source files in `Sources/Minimizer`, but the Xcode project is
generated. After adding or removing source files, run:

```sh
xcodegen generate
```

Then verify:

```sh
xcodebuild -project Minimizer.xcodeproj -scheme Minimizer -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Signing

`build_app.sh` signs with a stable local identity so the Accessibility TCC grant
persists across rebuilds. Do not replace it with plain ad-hoc signing for normal
testing or distribution.
