# Switch MTP 助手

一个适配 Intel Mac 的 macOS SwiftUI 应用，用来通过 Nintendo Switch DBI 的 MTP 响应器传输文件。

## 环境要求

- macOS 13 或更新版本
- Homebrew
- libmtp 命令行工具

安装 libmtp：

```bash
brew install libmtp
```

在 Intel Mac 上，Homebrew 通常会把工具安装到 `/usr/local/bin`。应用也会检查 `/opt/homebrew/bin`，方便以后迁移到 Apple silicon。

## Switch 设置

1. 用 USB 连接 Switch 和 Mac。
2. 打开 DBI。
3. 启动 DBI 的 MTP 响应器。
4. 在应用里点击“刷新”。
5. 在“目标存储区”选择位置。安装游戏通常选“5: SD Card install”。
6. 在“设备文件”里查看当前存储区内容。
7. 添加文件并上传。

## 构建和运行

```bash
./script/build_and_run.sh
```

脚本会构建 SwiftPM 可执行文件，生成 `dist/SwitchMTPBridge.app`，并以普通 macOS 应用方式启动。

## Release 打包

```bash
./script/package_app.sh
```

打包结果会生成到 `outputs/SwitchMTPBridge.app`。当前 release 版 helper 会动态链接 Homebrew 安装的 `libmtp` 和 `libusb`，使用前仍需安装 `libmtp`。

## 许可证和第三方依赖

本项目源码使用 MIT License。项目不包含 Nintendo、DBI、libmtp 或 libusb 的源码。

- `libmtp` 由 Homebrew 安装并在运行时动态链接，遵循其上游许可证。
- `libusb` 由 Homebrew 作为依赖安装并在运行时动态链接，遵循其上游许可证。
- Nintendo Switch、DBI、MTP responder 等名称仅用于描述兼容目标。
