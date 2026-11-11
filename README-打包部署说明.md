# 小捷·产销存 iPhone 版（Flutter）—— 打包部署说明

> 给徐总的 Mac 打包指引。代码已全部写好，按下面步骤在 Mac 上跑起来并打包上架即可。

---

## 一、你需要准备什么

| 项 | 说明 |
|---|---|
| 一台 Mac（苹果电脑） | 打包 iOS 必须用 Mac |
| 苹果开发者账号 | 99 美元/年，公司名义（青岛商捷电子有限公司）注册，需 D-U-N-S 编码 |
| Xcode | Mac App Store 免费下载 |
| Flutter SDK | 官网 https://flutter.dev 下载，装好配到 PATH |

---

## 二、第一次跑起来（验证功能）

### 1. 安装 Flutter

```bash
# 下载 Flutter SDK 后解压，加入 PATH（示例）
export PATH="$PATH:$HOME/flutter/bin"
flutter doctor
```

`flutter doctor` 会提示缺什么（Xcode、CocoaPods 等），按提示补齐。

### 2. 把本目录拷到 Mac 上

把 `flutter_app/` 整个目录拷到 Mac（U 盘 / 网盘 / 微信都行）。

### 3. 生成原生工程（iOS + Android）

Flutter 需要自动生成 Xcode 工程和 iOS 配置，在 `flutter_app/` 目录下执行：

```bash
cd flutter_app
flutter create . --org com.shangjie --project-name psc_app
```

这一步会生成 `ios/Runner.xcodeproj`、`ios/Runner/AppDelegate.swift`、`Info.plist` 等原生文件。

### 4. 接入原生桥（语音录音 + OCR）

我已经写好 iOS 原生桥文件 `ios/Runner/NativeBridge.swift`（语音录音 + Vision 中文 OCR）。

把它挂到 AppDelegate 上：打开 `ios/Runner/AppDelegate.swift`，改成这样（在 `didFinishLaunchingWithOptions` 里注册）：

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册原生桥（语音 + OCR）
    if let registrar = self.registrar(forPlugin: "NativeBridge") {
      NativeBridge.register(with: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

> 注意：`NativeBridge.swift` 文件要放进 Xcode 工程（拖进 Runner target，或确保它在 `ios/Runner/` 目录下被工程引用）。

### 5. 装依赖 + 跑起来

```bash
cd flutter_app
flutter pub get
flutter run
```

连上一台 iPhone（或模拟器），`flutter run` 就会编译并在手机上跑起来。

---

## 三、配置 iOS 权限（Info.plist）

打开 `ios/Runner/Info.plist`，加入这些权限描述（拍照、麦克风、相机）：

```xml
<key>NSCameraUsageDescription</key>
<string>用于扫码和拍照识别单据</string>
<key>NSMicrophoneUsageDescription</key>
<string>用于语音输入和语音播报</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>用于上传员工照片</string>
```

---

## 四、打包上架 App Store

```bash
cd flutter_app
flutter build ipa --release
```

然后用 Xcode 打开 `ios/Runner.xcworkspace`，配置签名（选你的苹果开发者账号 + 公司 Bundle ID），Archive 后上传 App Store Connect，提交审核。

---

## 五、功能清单（验收对照）

| 功能 | 状态 |
|---|---|
| 网页全部功能（登录/进销存/绩效/权限/看板/AI小捷/照片） | ✅ 加载同一网址，100% 一致 |
| 扫码 | ✅ mobile_scanner |
| 拍照 OCR 识单 | ✅ iOS Vision 中文识别 |
| 语音听写（讯飞，16k 流式） | ✅ 对齐安卓版协议 |
| 语音播报（讯飞，小蓉） | ✅ 对齐安卓版协议 |
| 蓝牙打印（佳博） | ❌ iPhone 不支持，已砍 |

---

## 六、注意事项

1. **讯飞语音鉴权**：密钥在云端，App 里不放密钥。网页会通过 `voiceSigned`/`speakSigned` 把云端签发的 wss 地址传给原生，原生直接连。这条链路已对齐安卓版。
2. **线上网址**：`https://psc-saas.app.workbuddy.host/?sharecode=YR6B4D4PZA`（写死在 `lib/main.dart` 的 `kWebUrl`）。
3. **版本号**：改 `pubspec.yaml` 的 `version` 和 `lib/main.dart` 的 `kAppVersion`，保持一致。
