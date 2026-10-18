# NotifyMeHow

A macOS menu bar app that lets you customize how notifications appear on your screen.

## Fork Notes

This fork of [mbinde/NotifyMeHow](https://github.com/mbinde/NotifyMeHow) includes the following additions and fixes:

- **Expressive Maple Mono Banner Renderer:** Renders custom notification cards using bundled `MapleMonoNormal-NF` (`Regular`, `Medium`, `Bold`) fonts, a compact icon-and-title header with an accent indicator dot, and automatic stripping of `[slk] ` transport prefixes from displayed titles after rule evaluation.
- **Mixed-Height Banner Stacking:** Positions stacked banners with a uniform 16-point vertical gap calculated from each window's actual rendered height, and reflows remaining banners when a window dismisses.
- **Clean System Notification & Alert Dismissal:** Invokes the native accessibility `Close` / `AXCancel` action on replaced banners and persistent system alerts (`AXNotificationCenterAlert`) while moving only the individual banner element off-screen instead of displacing the full-screen NotificationCenter hosting window.
- **Persistent Alert Deduplication & Multi-Banner Traversal:** Tracks processed notifications by their macOS `AXIdentifier` UUID in a bounded 500-entry set so persistent alerts never re-trigger, traverses all active notification containers in the NotificationCenter window rather than stopping at the first match, and restores off-screen NotificationCenter window coordinates on startup.
- **Prebuilt Apple Silicon Releases:** Bundles the Maple Mono fonts inside `NotifyMeHow.app` and publishes prebuilt `darwin-arm64` release archives via GitHub Actions.

## Why?

macOS notifications are easy to miss. They appear briefly in the corner, look the same whether it's a routine update or something urgent, and disappear before you notice them. Apps give you limited control: maybe an option for sounds or banners, but nothing that truly makes important notifications stand out.

NotifyMeHow fixes this. You can create rules that match notifications by app name or keywords, then apply custom styles that make them impossible to miss: larger size, different colors, screen-center positioning, attention-grabbing animations. When you enable "hide system notification," your custom notification completely replaces the default one—giving you full control over how that notification looks and behaves.

**Some examples:**
- Make Slack messages containing "urgent" or your name appear as large, red notifications in the center of your screen
- Keep routine notifications subtle while critical alerts demand attention
- Add pulsing or bouncing animations to notifications that need immediate action

## Features

NotifyMeHow can reposition system notifications to any corner or center of the screen. It also creates custom notification styles where you control position, size (0.5x to 3x scale), colors, opacity, display duration, icons, background images, and animations.

The rule system matches notifications by app name or keywords in the title and body. You can require all keywords to match or just any one of them. When a rule matches, it applies your chosen style—and if you've enabled "hide system notification," the default notification disappears entirely, replaced by your custom version.

Settings can be exported and imported, so you can back up your configuration or share it across machines.

## Installation

### Homebrew (recommended)

```bash
brew tap mbinde/tap
brew install --cask notifymehow
```

### Download Binary

Download the latest release from [GitHub Releases](https://github.com/alexgorbatchev/NotifyMeHow/releases), extract `NotifyMeHow.app`, and move it to `/Applications`.

### Build from Source

See [BUILDING.md](BUILDING.md) for instructions.

### First Run

Launch the app and it appears as an icon in your menu bar. macOS will prompt you to grant Accessibility permissions. Open **System Settings > Privacy & Security > Accessibility** and enable NotifyMeHow, then click "Start Monitoring" from the menu.

## Usage

### Repositioning Notifications

Select **Reposition To** from the menu to move all system notifications to a different location.

### Creating Custom Styles

Open **Settings** from the menu, go to the **Styles** tab, and click **Add Style**. Configure the appearance to your liking. Enable **Hide system notification** if you want your custom notification to replace the default entirely. You can also hide the icon, title, or body text individually.

### Setting Up Rules

In the **Rules** tab, click **Add Rule**. Set the app name and/or keywords to match, choose whether any keyword or all keywords must match, and select which style to apply. Rules are evaluated in order—the first match wins.

### Using Recent Notifications

The **Recent** tab shows notifications you've received while monitoring is active. Double-click any notification to create a rule from it—the app name and suggested keywords are pre-filled for you.

## Requirements

macOS 26 (Tahoe). Other versions are untested. Accessibility permissions required.

## Command Line

NotifyMeHow also works from the terminal. Run `NotifyMeHow --help` for options, or just launch the app bundle to use the menu bar interface.

## License

GPL-3.0. See [LICENSE](LICENSE) for details.
