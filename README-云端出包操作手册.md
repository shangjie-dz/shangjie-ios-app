# 小捷·产销存 iPhone 版 —— 云端出包操作手册（给徐总）

> 仓库：`D:\WorkBuddy\shangjie-ios-app\`  
> 原理：GitHub 免费提供"云端苹果电脑"，代码推上去自动编译出 iPhone 安装包（ipa），**您不需要有一台 Mac**。

---

## 第一步：注册 GitHub 账号（5 分钟，免费）

1. 浏览器打开 <https://github.com/signup>
2. 用公司手机号能收验证码的邮箱注册（推荐微信/ QQ 邮箱都行）
3. 用户名建议：`shangjie-dz`（商捷电子），好记

## 第G二步：建仓库并上传代码

注册好后**把用户名告诉小捷**，小捷帮您把代码推上去（推荐，省事）。

如果想自己动手：

1. 登录 GitHub → 右上角 + → New repository → 名字填 `shangjie-ios-app` → 选 **Private** → Create
2. 电脑上打开命令行，执行（把 `你的用户名` 换掉）：

```bash
cd /d/WorkBuddy/shangjie-ios-app
git init
git add .
git commit -m "商捷产销存 iPhone 版"
git branch -M main
git remote add origin https://github.com/你的用户名/shangjie-ios-app.git
git push -u origin main
```

1. 弹出登录窗口时用浏览器授权即可。

## 第三步：云端自动出包，下载 ipa

1. 代码推上去后，打开 GitHub 仓库页面 → 顶部 **Actions** 标签
2. 等待构建（约 10-15 分钟，绿勾=成功）
3. 点进构建记录 → 底部 **Artifacts** → 下载 `psc_app_unsigned_ipa`（解压得到 ipa）

## 第四步：装进 iPhone（二选一）

### A. 先试用（0 成本，7 天有效）

1. Windows 电脑装 **爱思助手**（i4.cn）或 Sideloadly
2. iPhone 连电脑，用您的普通 Apple ID（免费的就行）给 ipa 签名安装
3. iPhone 上：设置 → 通用 → VPN与设备管理 → 信任开发者证书
4. 缺点：**7 天后要重签一次**——适合先给几个人试效果

### B. 正式长期用（99 美元/年）

1. 申请 D-U-N-S 编码（免费，邓白氏官网，用营业执照，5-7 个工作日）
2. 以公司名义注册 Apple Developer（developer.apple.com）
3. 小捷把正式签名接进云端流水线，之后出 TestFlight 版：员工直接下载、**永久有效、自动更新**

---

## 仓库里都有什么

| 文件                                | 作用                                    |
| --------------------------------- | ------------------------------------- |
| `lib/`                            | App 全部代码（WebView 外壳 + 扫码/OCR/语音 4 个桥） |
| `ios/Runner/NativeBridge.swift`   | iOS 原生桥（讯飞语音 + Vision 中文识别）           |
| `scripts/prepare_ios.sh`          | 云端自动生成 iOS 工程 + 挂桥 + 权限 + 图标          |
| `.github/workflows/build-ios.yml` | 云端出包流水线（推代码即自动编译）                     |
| `README-打包部署说明.md`                | 原 Mac 手动打包说明（备用，云端走通后用不上）             |

## 每次改版怎么发新包

改完代码 → 推送到 GitHub → Actions 自动出新 ipa → 下载安装。全程不用碰苹果电脑。
