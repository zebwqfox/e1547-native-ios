# E1547 Native iOS

![平台](https://img.shields.io/badge/platform-iOS%2026-black)
![Swift](https://img.shields.io/badge/Swift-native-orange)
![状态](https://img.shields.io/badge/status-MVP-blue)
![许可证](https://img.shields.io/badge/license-GPL--3.0-lightgrey)

语言：[English](README.md) | 简体中文

E1547 Native iOS 是 E1547 的 Swift 原生 iOS 衍生版本。它从 iOS 优先的体验重新出发，用原生 SwiftUI 构建 e621/e926 浏览客户端。

这个仓库刻意和原来的多平台 Flutter 项目分开。当前目标是 iOS 26 原生 MVP：使用 SwiftUI、系统媒体能力、Keychain 凭据保存、相册保存和更贴近 iOS 的交互方式。

## 功能亮点

| 模块 | 内容 |
| --- | --- |
| 账号 | 使用 e621 用户名 + API key 登录，凭据存入 Keychain |
| 浏览 | 搜索、热门、收藏、标签自动补全、黑名单过滤 |
| 媒体 | 图片、GIF、可播放 MP4 视频分辨率版本、视频质量设置 |
| 详情页 | SQE 分级徽章、元数据、来源、标签、评论、收藏和投票 |
| 查看器 | 点击图片放大全屏、下滑退出、详情页左右滑切换上一张/下一张 |
| 翻译 | 使用 `deepseek-v4-flash` 翻译简介和评论 |
| 保存 | 图片、GIF、视频保存到系统相册里的 `E1547` 相簿 |
| 原生手感 | 触感反馈、PIN 锁、生物识别解锁、iOS 26 目标、面向 Liquid Glass 的界面方向 |

## 项目结构

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
    └── 从原项目继承的少量构建/版本 xcconfig 文件
```

`Flutter` 文件夹目前只是为了保留原 Xcode 工程仍在引用的少量 xcconfig 和版本值。运行时应用本身是 Swift 原生实现。

## 环境要求

- macOS 和 Xcode 17 或更新版本
- iOS 26 SDK
- e621/e926 账号 API key
- 可选：DeepSeek API key，用于翻译

## 用 Xcode 打开

```bash
open Runner.xcodeproj
```

无签名模拟器构建：

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

## 构建给 Sideloadly 使用的未签名 IPA

Sideloadly 可以重新签名标准 `Payload/*.app` 结构的 IPA。先构建未签名真机包，再打包：

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

生成的 `e1547-sideloadly-unsigned.ipa` 可以导入 Sideloadly。

## 隐私和凭据

- e621 凭据用于 HTTP Basic Auth。
- e621 用户名和 API key 本地存入 Keychain。
- DeepSeek API key 本地存入 Keychain。
- 相册权限仅用于创建 `E1547` 相簿并保存媒体。

## 当前状态

这是早期原生 MVP。当前重点是把 SwiftUI 客户端打磨到足够适合日常使用，之后再继续清理继承的工程命名和剩余旧 Xcode 结构。

## 免责声明

这是非官方客户端，与 e621、e926 或 DeepSeek 没有关联。请负责任地使用，并遵守连接服务的相关条款。
