# Changelog

## 2026-06-14

- Released `v1.0.0` as a notarized Developer ID app ZIP.
- Added a README download link for GitHub Releases.
- Fixed release script variable boundaries around progress messages.
- Added an optimized README demo GIF and ignored raw screen recordings.
- Removed personal Apple Developer Team metadata from public project files.
- Replaced the fixed local signing-keychain password with a generated per-machine
  password file outside the repository.
- Expanded ignore rules for signing keys and provisioning profiles.
- Added the app icon to the top of the GitHub README.
- Prepared the project for a public GitHub launch.
- Rewrote the README for open-source users and contributors.
- Added MIT licensing, GitHub issue templates, and CI workflow configuration.
- Added a SwiftPM test target so `swift test` validates shortcut helper behavior.
- Updated CI checkout and Homebrew setup for current hosted macOS runners.
- Disabled AppIntents metadata extraction for the non-AppIntents app target.
- Fixed the local signing fallback so CI machines without Apple signing identities
  can still build the app bundle.
- Tightened ignore rules for local build artifacts, app bundles, and private
  scratch files.

## 2026-06-05

- Restored focus-last restore sequencing after the all-at-once restore trial did not
  produce a visible UX win.
- Added concise onboarding and Settings copy explaining that Minimizer prioritizes
  focus restoration while macOS controls visible animation timing.
- Added restore batching tests to lock the focus-last restore behavior.
- Disabled unused AppIntents const metadata emission in the Xcode project settings.
- Added restore-settling logic so background windows restore first, then the original
  focused window is restored and focused once at the end.
- Added SwiftPM regression tests for restore settling timeout and stability behavior.
- Fixed `build_app.sh` shell expansion and self-signed fallback issues in the stable
  signing path.
- Removed unused icon generator variants and old icon preview files.
- Added required project documentation files and corrected stale engine notes.
