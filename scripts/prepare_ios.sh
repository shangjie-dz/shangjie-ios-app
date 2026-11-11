#!/usr/bin/env bash
# 在云端 Mac 上自动完成 iOS 工程生成、原生桥挂载、权限声明、图标生成
set -e
cd "$(dirname "$0")/.."

echo "== 1/4 生成 iOS 原生工程 =="
flutter create . --platforms ios --org com.shangjie --project-name psc_app

echo "== 2/4 挂载原生桥（语音 + OCR）=="
cp ios-overrides/AppDelegate.swift ios/Runner/AppDelegate.swift

echo "== 3/4 写入相机/麦克风/相册权限 =="
PLIST=ios/Runner/Info.plist
plutil -insert NSCameraUsageDescription -string "用于扫码和拍照识别单据" "$PLIST" 2>/dev/null || true
plutil -insert NSMicrophoneUsageDescription -string "用于语音输入和语音播报" "$PLIST" 2>/dev/null || true
plutil -insert NSPhotoLibraryUsageDescription -string "用于上传员工照片" "$PLIST" 2>/dev/null || true

echo "== 4/4 生成应用图标 =="
dart run flutter_launcher_icons || true

flutter pub get
echo "== iOS 工程准备完成 =="
