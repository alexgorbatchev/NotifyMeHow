# Building NotifyMeHow

## Prerequisites

- macOS 26 (Tahoe) — other versions untested
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Install

```bash
# Clone the repository
git clone https://github.com/mbinde/NotifyMeHow.git
cd NotifyMeHow

# Build and create app bundle
./create-app.sh

# Install to Applications (optional)
cp -r NotifyMeHow.app /Applications/
```

## Running

```bash
# From the build directory
open NotifyMeHow.app

# Or if installed
open /Applications/NotifyMeHow.app
```

On first launch, macOS will prompt for Accessibility permissions. Grant access in **System Settings > Privacy & Security > Accessibility**.

## CLI Mode

The app also supports command-line usage for scripting:

```bash
.build/debug/NotifyMeHow --help
```

## Development

The `justfile` wraps the local development loop:

```bash
# Rebuild and sign, quit any running NotifyMeHow, apply notifymehow.local.json,
# launch the local build
just run

# Send test notifications for NotifyMeHow to restyle
just test-notifications

# Run tests
just test
```

`notifymehow.local.json` uses the Settings > Export format. `just run` imports it with
`NotifyMeHow --import-settings`, which replaces settings, styles and rules but leaves
launch-at-login unchanged. Image paths may start with `~`. `defaultStyleId` picks the style
used when no rule matches.

A style with `baseStyleId` lists only the fields it changes and inherits the rest from that
style (bases can chain). The style editor's "Based On" menu sets it and saves only the
fields that differ from the base. Deleting a base style copies its values into the styles
based on it, so their appearance does not change.

`just build` signs with a Developer ID (override with `NOTIFYMEHOW_SIGNING_IDENTITY`), so
the Accessibility permission granted once in System Settings > Privacy & Security >
Accessibility survives rebuilds. `./create-app.sh` alone signs ad hoc (or with
`CODESIGN_IDENTITY`); ad-hoc builds are trusted per binary and lose the permission on every
rebuild. `just reset-permissions` clears the permission when you want a fresh prompt.

```bash
# Build only (no app bundle)
swift build

# Run tests
swift test

# Build release version
swift build -c release
```

## Creating a Release

To create a signed, notarized release for distribution:

```bash
./release.sh
```

This requires a Developer ID Application certificate and notarization credentials stored in your Keychain. See the comments in `release.sh` for setup instructions. The script produces `release/NotifyMeHow.zip` ready for upload to GitHub Releases.
