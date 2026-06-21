# E1547 Native iOS

![Platform](https://img.shields.io/badge/platform-iOS%2026-black)
![Swift](https://img.shields.io/badge/Swift-native-orange)
![Status](https://img.shields.io/badge/status-MVP-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey)

E1547 Native iOS is a Swift-native derivative of E1547, rebuilt as an iOS-first client for browsing e621/e926 with a focused native interface.

This repository intentionally keeps the native iOS application separate from the original multi-platform Flutter project. The app starts from an iOS 26 MVP and leans into native SwiftUI, system media handling, Keychain credentials, Photo Library saving, and iOS interaction patterns.

## Highlights

| Area | What is included |
| --- | --- |
| Account | e621 login with username plus API key, stored in Keychain |
| Browsing | Search, popular feed, favorites, tag autocomplete, denylist filtering |
| Media | Images, GIFs, playable MP4 video variants, configurable video quality |
| Detail View | SQE rating badges, metadata, sources, tags, comments, favorite and vote actions |
| Viewer | Tap image to expand with animation, swipe down to dismiss, swipe detail page left or right to switch posts |
| Translation | DeepSeek translation for descriptions and comments using `deepseek-v4-flash` |
| Saving | Save images, GIFs, and videos into an `E1547` album in Photos |
| Native Feel | Haptics, PIN lock, biometric unlock, iOS 26 target, Liquid Glass-friendly layout direction |

## Project Shape

```text
.
├── Runner.xcodeproj
├── Runner
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── Info.plist
│   ├── Assets.xcassets
│   └── Native
│       ├── NativeRootView.swift
│       ├── BrowseView.swift
│       ├── PostDetailView.swift
│       ├── MediaView.swift
│       ├── E621APIClient.swift
│       ├── E621Models.swift
│       ├── E621Preferences.swift
│       ├── DeepSeekTranslator.swift
│       └── ...
└── Flutter
    └── minimal inherited build/version xcconfig files
```

The `Flutter` folder is currently kept only because the inherited Xcode project still uses a few xcconfig/version values from the original project. The runtime app is Swift native.

## Requirements

- macOS with Xcode 17 or newer
- iOS 26 SDK
- e621/e926 account API key
- Optional: DeepSeek API key for translation

## Open In Xcode

```bash
open Runner.xcodeproj
```

For simulator builds without signing:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project Runner.xcodeproj \
  -scheme Runner \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build \
  CODE_SIGNING_ALLOWED=NO
```

## Build An Unsigned IPA For Sideloadly

Sideloadly can re-sign a standard `Payload/*.app` IPA. Build the device app without signing, then package it:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project Runner.xcodeproj \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath build/ios_device_unsigned \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''

rm -rf build/sideloadly_ipa
mkdir -p build/sideloadly_ipa/Payload
cp -R build/ios_device_unsigned/Build/Products/Release-iphoneos/Runner.app \
  build/sideloadly_ipa/Payload/Runner.app

cd build/sideloadly_ipa
zip -qry ../../e1547-sideloadly-unsigned.ipa Payload
```

The resulting `e1547-sideloadly-unsigned.ipa` can be imported into Sideloadly.

## Privacy And Credentials

- e621 credentials are used for HTTP Basic Auth.
- e621 username and API key are stored locally in Keychain.
- DeepSeek API key is stored locally in Keychain.
- Photo Library access is used only to create and save into the `E1547` album.

## Status

This is an early native MVP. The current focus is making the SwiftUI client pleasant and complete enough for daily use before cleaning up inherited project naming and any remaining legacy Xcode structure.

## Disclaimer

This is an unofficial client. It is not affiliated with e621, e926, or DeepSeek. Use responsibly and follow the terms of the services you connect to.
