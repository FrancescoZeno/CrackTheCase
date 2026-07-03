# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

CrackTheCase is an Xcode project currently at the default SwiftUI + SwiftData
template stage (no custom app logic has been written yet). It defines two
native app targets that share nearly identical source, one per platform:

- **CrackTheCase** — tvOS target (`SDKROOT = appletvos`), source in `CrackTheCase/`.
- **CrackTheCaseIos** — iOS target (`SDKROOT = iphoneos`, iPhone + iPad), source in `CrackTheCaseIos/`.

Each target has its own `<Target>App.swift` (App entry point + SwiftData
`ModelContainer` setup), `ContentView.swift`, and `Item.swift` (a trivial
`@Model` with a single `timestamp: Date`). The two targets are not code-shared
via a common framework — when editing shared logic (e.g. the `Item` model),
check whether the change needs to be applied to both
`CrackTheCase/Item.swift` and `CrackTheCaseIos/Item.swift`. The iOS
`ContentView` additionally has an `EditButton()` toolbar item that the tvOS
version does not.

There are no test targets, no README, and no third-party dependencies
(no SPM packages, no CocoaPods/Carthage) in this project yet.

## Common commands

Build/run is via Xcode or `xcodebuild` from the repo root (where
`CrackTheCase.xcodeproj` lives).

```bash
# List schemes/targets
xcodebuild -list -project CrackTheCase.xcodeproj

# Build the iOS target for the simulator
xcodebuild -project CrackTheCase.xcodeproj -scheme CrackTheCaseIos \
  -destination 'generic/platform=iOS Simulator' build

# Build the tvOS target for the simulator
xcodebuild -project CrackTheCase.xcodeproj -scheme CrackTheCase \
  -destination 'generic/platform=tvOS Simulator' build
```

There is no test target configured, so `xcodebuild test` will not work until
one is added.
