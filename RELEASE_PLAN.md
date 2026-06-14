# Minimizer — Release Plan (Direct Notarized Distribution)

## Decision
Mac App Store is **not viable**: new MAS apps must be sandboxed, and sandboxed apps
cannot use the Accessibility API to control other apps' windows (the app's core
engine). Distribution channel = **Developer ID-signed + notarized .dmg**, hosted on
a website / GitHub Releases. Free for users. Same model as Rectangle.

## Engine: Direct AXMinimized
- Current engine: direct Accessibility commands per window using
  `kAXMinimizedAttribute`.
- Rejected engines stay rejected: `NSRunningApplication.hide()`,
  `NSApplication.hideOtherApplications(nil)`, and Mission Control Show Desktop
  triggers.
- Accessibility permission is required because the app controls other apps' windows.

## Project format
- Converted from SwiftPM to a proper Xcode app project via XcodeGen.
  Source of truth: project.yml → `xcodegen generate` → Minimizer.xcodeproj.
  App target, bundle id com.equinox.Minimizer, Hardened Runtime ON.
  ⌘R builds a real Minimizer.app bundle. (Package.swift + build_app.sh kept as CLI fallback.)

## Prerequisites (one-time account setup)
- [ ] Apple Developer Program membership.
- [ ] **Developer ID Application** certificate — NOT the same as the "Apple Development"
      cert used for local development. Create via Xcode → Settings → Accounts → Manage
      Certificates → "+" → Developer ID Application. (Required for notarization.)
- [ ] notarytool credentials: an App Store Connect API key (preferred) or an
      app-specific password, stored once via `xcrun notarytool store-credentials`.

## Phase 1 — Product polish (features users expect)
- [x] Animation: full-screen overlays were tried (glass sweep/ripple/aurora/light
      sweep/iris) and ALL read cheap — decision: removed entirely. Replaced with a
      subtle, contained menu-bar ICON micro-animation (tuck on minimize, pop on
      restore). AnimationOverlay.swift deleted. Premium through restraint.
- [x] App icon (.icns, all sizes) — blue→purple squircle, white window/arrow, fan of
      colorful glass panels behind the window, frosted dock with GENERIC colorful
      tiles. tools/gen_icon_v5.swift. ✅ Trademark-safe (real Apple icons removed;
      Apple legal explicitly forbids reusing their icon artwork). v4 (real icons)
      kept for personal use only.
- [x] First-run onboarding window: app icon, what-it-does, hotkey, Accessibility
      explainer + Enable button (live ✓ status), Get Started. Shows once (UserDefaults
      didCompleteOnboarding). Shared Accessibility helper centralizes AX logic.
- [x] Preferences window (AppKit) — Settings… menu item (⌘,):
      - [x] Customizable global hotkey via a click-to-record control (persisted in
            UserDefaults; HotKeyCenter re-registers live). Restore Default button.
      - [x] Launch at Login checkbox (shared LoginItem helper; also still in menu)
      - [x] Open Accessibility Settings button
      - [ ] Exclude-apps list (never minimize selected apps) — deferred to next pass
- [ ] About window: version, website, license, credits
- [ ] Edge-case pass: windows on other Spaces, multiple displays, fullscreen

## Phase 2 — Auto-update
- [ ] Integrate **Sparkle** framework (the standard for non-MAS Mac apps)
- [ ] Host an appcast.xml + signed update feed (EdDSA key)

## Phase 3 — Signing, notarization, packaging  [release.sh AUTOMATES THIS]
- release.sh is written + executable. Runs once two prereqs exist:
  (a) Developer ID Application cert in keychain. Create via Xcode → Settings →
      Accounts → Manage Certificates → + → Developer ID Application.
  (b) notary creds stored: `xcrun notarytool store-credentials "MinimizerNotary"
      --key AuthKey_XXX.p8 --key-id KEYID --issuer ISSUERID`.
  Then: `./release.sh` → signed + notarized + stapled Minimizer.dmg.
- Tooling confirmed: notarytool, stapler (Xcode), hdiutil for DMG. create-dmg not needed.
- [ ] Re-sign with **Developer ID Application** cert + **Hardened Runtime**
      (`codesign --options runtime`)
- [ ] Build a `.dmg` (create-dmg or hdiutil) with drag-to-Applications layout
- [ ] Notarize: `xcrun notarytool submit Minimizer.dmg --wait`
- [ ] Staple: `xcrun stapler staple Minimizer.dmg`
- [ ] Verify on a clean account: download → no Gatekeeper block → grant → works

## Phase 4 — Distribution & presentation
- [ ] Landing page (or GitHub repo) with screenshots + download button
- [ ] (Optional) Open-source under MIT, host .dmg on GitHub Releases
- [ ] Privacy note: app collects nothing, no network except update check
- [ ] Version/changelog discipline

## Notes / risks
- Hardened Runtime + Accessibility: fine together; no special entitlement needed for
  a non-sandboxed Developer ID app. The user grants Accessibility at runtime as today.
- Sparkle requires the hardened-runtime exception entitlements for its XPC services —
  documented, standard.
- Keep the stable-signature lesson: notarized Developer ID signature is stable across
  rebuilds, so Accessibility grant persists for end users across app updates.
