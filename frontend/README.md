<div align="center">

# CodeAgent Hub

[![Version](https://img.shields.io/badge/version-1.1.1-blue.svg)](../../releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey.svg)](../../releases)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg)](https://flutter.dev/)

一个统一的多平台界面，用于与 Claude Code 和 Codex 方便的进行交互。

服务端: [链接待补充]

</div>

## 功能特性

- **双后端支持**: 同时支持 Claude Code 和 Codex 两种 AI 代理
- **多标签页管理**: 同时进行多个对话，自由切换
- **流式消息**: 实时显示 AI 回复，支持中断，几乎原生的Claude Code使用体验
- **图片支持**: 支持发送图片
- **跨平台**: Windows、macOS、Linux、Android、iOS 全平台支持

## 下载安装

### 系统要求

- **Windows**: Windows 10 及以上
- **macOS**: macOS 10.15 (Catalina) 及以上
- **Linux**: Ubuntu 22.04+ / Debian 11+ / Fedora 34+
- **Android**: Android 6.0 及以上

### 直接下载

从 [Releases](../../releases) 页面下载对应平台的安装包：

- **Windows**: `CodeAgentHub-v{version}-Windows.zip`
- **macOS**: `CodeAgentHub-v{version}-macOS.zip`
- **Linux**: `CodeAgentHub-v{version}-Linux.zip`
- **Android**: `CodeAgentHub-v{version}-Android.apk`

### 从源码构建

#### Windows

1. **安装 Flutter**

```powershell
# 方式1: 使用 winget (推荐，Windows 11 自带)
winget install --id=Flutter.Flutter -e

# 方式2: 使用 Chocolatey
choco install flutter

# 方式3: 使用 Scoop
scoop install flutter

# 方式4: 手动下载
# 从 https://docs.flutter.dev/get-started/install/windows 下载 zip
# 解压后将 flutter\bin 添加到系统 PATH
```

2. **安装 Visual Studio**
   - 下载 [Visual Studio 2022](https://visualstudio.microsoft.com/) 或 [Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
   - 安装时勾选 "使用 C++ 的桌面开发" 工作负载

3. **验证安装**

```powershell
flutter doctor
```

#### macOS

1. **安装 Flutter**

```bash
# 使用 Homebrew (推荐)
brew install --cask flutter

# 或手动下载
# https://docs.flutter.dev/get-started/install/macos
```

2. **安装 Xcode**

```bash
xcode-select --install
sudo xcodebuild -license accept
```

3. **验证安装**

```bash
flutter doctor
```

#### Linux

1. **安装 Flutter**

```bash
# 使用 snap (推荐)
sudo snap install flutter --classic

# 或手动下载
# https://docs.flutter.dev/get-started/install/linux
```

2. **安装开发依赖**

```bash
# Ubuntu/Debian
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# Fedora
sudo dnf install clang cmake ninja-build gtk3-devel
```

3. **验证安装**

```bash
flutter doctor
```

#### Android (可选)

如需构建 Android 版本：

1. 安装 [Android Studio](https://developer.android.com/studio)
2. 在 SDK Manager 中安装 Android SDK 和 Command-line Tools
3. 运行 `flutter doctor` 确认 Android 工具链已就绪

---

#### 通用步骤

完成上述平台特定步骤后，执行以下通用步骤：

**克隆并运行**

```bash
# 克隆项目
git clone <repository-url>

# 安装依赖
flutter pub get

# 运行（调试模式）
flutter run -d windows  # 或 macos / linux
```

**构建发行版**

```bash


# 或手动构建
flutter build windows --release
# 然后手动复制 scripts 文件夹到 build/windows/x64/runner/Release/

# macOS
flutter build macos --release
# 产物: build/macos/Build/Products/Release/CodeAgent Hub.app

# Linux
flutter build linux --release
# 产物: build/linux/x64/release/bundle/

# Android
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk

# iOS (需要 macOS + Xcode)
flutter build ios --release
```

## 使用方式

### 基础使用

1. 在本地电脑启动后端服务（服务端链接见上方）
2. 在任意设备上打开 CodeAgent Hub 应用
3. 在登录界面输入本地电脑的 IP 地址（如 `http://192.168.1.100:8000`）
4. 登录后即可在手机、平板等设备上远程使用电脑上的 Claude Code / Codex

> 提示：确保本地电脑和使用设备在同一局域网内，或配置好端口转发/内网穿透

### Windows 右键菜单集成

Windows 用户可以安装右键菜单集成，实现从任意文件夹快速打开对话：

#### 使用

安装后，在任意文件夹：
- **右键文件夹**：选择"使用 CodeAgent Hub 打开"
- **在文件夹内空白处右键**：选择"在此处使用 CodeAgent Hub"

应用会自动：
- 如果应用未运行，启动并打开对话
- 如果应用已运行，在现有窗口的新标签页中打开对话（单实例功能）


## 常见问题

**Q: flutter doctor 显示缺少依赖？**

A: 根据提示安装对应平台的开发工具。Windows 需要 Visual Studio，macOS 需要 Xcode，Linux 需要 GTK 开发库。

**Q: 构建报错找不到 SDK？**

A: 运行 `flutter doctor -v` 查看详细信息，确保已正确安装对应平台的 SDK。

**Q: macOS 提示"无法验证开发者"？**

A: 前往 "系统设置" → "隐私与安全性" → 点击 "仍要打开"。

## 技术栈

**Frontend**: Flutter 3.5 · Dart · Riverpod · Dio

**Platforms**: Windows · macOS · Linux · Android · iOS

## 许可证

[待补充]
