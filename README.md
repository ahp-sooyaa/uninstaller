# Uninstaller

Right-click an app in Finder and choose **Uninstall**. Uninstaller finds what the app left around your Mac — caches, preferences, containers, saved state, launchd jobs and privileged helpers — and moves the app and the items you pick to the Trash, so every uninstall can be undone.

## Features

- **Finder integration:** an Uninstall item in the right-click menu, through a bundled Finder Sync extension.
- **Careful matching:** the app's bundle ID, team ID, its own helpers and extensions, App Groups, and other copies of the same app.
- **About 20 locations scanned** in `~/Library` and `/Library`: Application Support, Containers, Group Containers, Caches, HTTPStorages, WebKit, Preferences, Cookies, Saved Application State, Logs, LaunchAgents, LaunchDaemons and PrivilegedHelperTools.
- **Safe defaults:** exact bundle ID matches are ticked; name-only matches are listed but left for you to choose.
- **Trash, not delete:** everything goes to the Trash. The app is removed first; if that fails, its data stays.
- **Background jobs are stopped** (`launchctl unload`) before their plists are moved.
- **One admin prompt** for all items in folders you can't write to.
- Refuses apps without a bundle ID and protected system apps.

## Requirements

- macOS 14 or later
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and install

```sh
git clone https://github.com/ahp-sooyaa/uninstaller.git
cd uninstaller
./install.sh
```

`install.sh` generates the Xcode project, builds a Release copy, installs it to `/Applications`, and registers the Finder extension. Then turn on **Uninstaller** under Finder extensions in System Settings (General → Login Items & Extensions).

## Project layout

| Path | Role |
| --- | --- |
| `Uninstaller/Scanner.swift` | Identifies the app and finds its leftovers |
| `Uninstaller/Remover.swift` | Quits the app, stops background jobs, moves items to the Trash |
| `Uninstaller/UninstallModel.swift` | Scan and removal state for the UI |
| `Uninstaller/ContentView.swift` | The review window |
| `FinderExtension/FinderSync.swift` | Finder right-click menu item |
| `project.yml` | XcodeGen project definition |
| `design/` | App icon sources (SVG) |

## Status

Work in progress. An optional review by Claude Code (paths only, never file contents) for leftovers the rules miss is in development.

## License

[MIT](LICENSE)
