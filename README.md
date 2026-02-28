# FIXLens

A macOS native FIX protocol message parser. Paste raw FIX text or open a log file to get a human-readable timeline of messages with full field-level detail.

## Requirements

- macOS 15 or later
- Xcode command-line tools (`xcode-select --install`)

## Development

### Run during development

```bash
swift run
```

Compiles and launches the app directly. Fast iteration — no `.app` bundle is created. The Dock will show a generic icon in this mode, which is expected.

### Open in Xcode

```bash
open Package.swift
```

Xcode opens the Swift package as a project. Full debugger, SwiftUI previews, and instruments support.

## Building a distributable app

```bash
./build-app.sh
```

This script:
1. Compiles a release binary (`swift build -c release --arch arm64`)
2. Assembles `FIXLens.app` with the correct macOS bundle structure
3. Converts the icon assets to `AppIcon.icns` via `iconutil`
4. Writes `Info.plist` with the bundle identifier, icon reference, and minimum OS version

The finished `FIXLens.app` appears in the project root. Launch it with:

```bash
open FIXLens.app
```

### Install to Applications

```bash
cp -R FIXLens.app /Applications/
```

### Zip for sharing

```bash
zip -r FIXLens.zip FIXLens.app
```

## Updating the app icon

Icon source files live in:

```
Sources/FIXLens/Resources/Assets.xcassets/AppIcon.appiconset/
```

Replace the PNG files there, then re-run `./build-app.sh`. The script regenerates `AppIcon.icns` from the PNG files on every build.

## Project structure

```
Sources/FIXLens/
  FIXLensApp.swift              App entry point, menu commands, About window
  ContentView.swift             Main split-view layout
  Models/
    FIXDictionary.swift         Field and message definitions
    FIXMessage.swift            Parsed message model
  Services/
    FIXDictionaryLoader.swift   Loads FIX44.xml from the bundle
    FIXParser.swift             Auto-detects delimiter; streams parse results
  ViewModels/
    AppViewModel.swift          @Observable state; async filtering
  Views/
    PasteInputView.swift        Text input + Parse button
    TimelineView.swift          Message table with filter bar
    FilterBarView.swift         Type / Side / Status pickers
    DetailView.swift            Per-message field detail panel
    AboutView.swift             About window
  Resources/
    FIX44.xml                   Bundled FIX 4.4 data dictionary
    Assets.xcassets/            App icon asset catalog
```
