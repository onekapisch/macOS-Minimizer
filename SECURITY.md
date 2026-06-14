# Security

## Permissions

Minimizer requires macOS Accessibility permission to minimize, restore, and focus
windows belonging to other apps. It does not request sandbox entitlements because the
direct distribution build needs Accessibility control.

## Secrets

Do not commit API keys, passwords, signing credentials, notary credentials, or real
`.env.local` files. This project does not require runtime environment variables.

## Data Handling

Minimizer does not collect, transmit, or persist document contents. Window references
are held in memory only for the active minimize/restore cycle and are cleared after
restore.

## Network

The current app has no network behavior. Future auto-update support must document the
update endpoint and signing model before release.

## Retention

No user data is retained by the app. Preferences such as onboarding completion,
hotkey choice, and Launch at Login state are stored locally through macOS defaults and
system services.
