# Mac Sticky Notes

A small, native macOS sticky-notes app in the spirit of Microsoft Sticky Notes: notes sit on your
desktop, come in several colours, and are easy to manage. Built with Swift (SwiftUI + AppKit).

Working name — the app may be renamed before any release.

## Features

- **Notes on the desktop** — borderless pastel notes; move and resize freely. Each note can be kept
  on top and can appear on all desktops (Spaces) or just one.
- **Colours** — four presets (yellow, pink, blue, green) plus any custom colour from the system colour
  panel. Text switches to white on dark colours.
- **Simple editor** — bold (⌘B), italic (⌘I), bullet lists (`- `), checklists (`[] `, click to tick),
  plain-text paste. Notes are stored as Markdown.
- **Manager window** — card grid with full-text search, colour filter, sorting, multi-select,
  and a trash (kept 30 days).
- **Menu bar app** — no Dock icon. Global shortcut for a new note (default ⌃⌥N, changeable).
- **Local only** — one JSON file per note, a daily backup (last 7 kept), export all notes as `.md`.
- English and Traditional Chinese.

## Requirements

macOS 14 or later, Xcode 16+ (Swift 6 toolchain).

## Build and run

```bash
swift test                    # unit tests (Markdown, store, search, rich-text bridge)
Scripts/package-app.sh        # builds build/Mac Sticky Notes.app (sandboxed, ad-hoc signed)
open "build/Mac Sticky Notes.app"
```

Developer hook: `open -n "build/Mac Sticky Notes.app" --args --export-to <folder inside the sandbox container>` exports all notes at launch and logs the result.

Pass `SIGN_ID="Apple Development: …"` to sign with a real identity.

## Layout

| Path | What it holds |
| --- | --- |
| `Sources/StickyCore` | Testable core: Markdown model, rich-text bridge, note store, search, colours |
| `Sources/MacStickyNotes` | The app: windows, editor, manager, settings, menu bar |
| `Tests/StickyCoreTests` | Unit tests for the core |
| `Design/AppIcon.svg` | App icon source (redraw of a yellow note with orange clip and an idea bulb); `Scripts/render-icon.swift` renders it to `AppIcon.png` |
| `Scripts/package-app.sh` | Builds the `.app` bundle with Info.plist and sandbox entitlements |

The app runs in the App Sandbox from the start, so it can later go to the Mac App Store.
