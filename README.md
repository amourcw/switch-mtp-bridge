# MTP 文件传输

适配 Intel Mac 的双栏 macOS 文件传输应用。左侧浏览本机目录，右侧浏览任意兼容 MTP 的设备目录，可在两侧之间复制文件或文件夹。

兼容目标包括 Android 手机、相机、播放器，以及开启 MTP 响应器的 Nintendo Switch DBI。DBI 的 `SD Card install` 会在可用时作为默认存储区，仍可从顶部菜单切换到其他存储区。

## 使用前准备

- macOS 13 或更新版本
- Homebrew
- `libmtp`

```bash
brew install libmtp
```

插入设备并在设备端开启 MTP 模式后，打开应用并点击工具栏的刷新按钮。选择顶部的设备存储区后，即可双击文件夹进入目录；选择项目后，使用底部的方向按钮即可传输。传输会显示在底部队列，失败项目可用播放按钮重试。

## Switch DBI

1. 用 USB 连接 Switch 和 Mac。
2. 在 DBI 中启动 MTP Responder。
3. 刷新应用，顶部选择 `SD Card install` 以安装文件，或选择其他存储区浏览文件。

## 构建

```bash
./script/build_and_run.sh
```

运行后会生成 `dist/MTPFileTransfer.app`。发布打包：

```bash
./script/package_app.sh
```

会生成 `outputs/MTPFileTransfer.app`。应用运行时动态链接 Homebrew 的 `libmtp` 与 `libusb`，因此目标 Mac 也需要先执行 `brew install libmtp`。

## 许可证

项目源码使用 MIT License，不包含 Nintendo、DBI、libmtp 或 libusb 的源码。第三方运行时依赖遵循其各自上游许可证。

应用图标为本项目生成的原创视觉资产，随源码以 `Assets/AppIcon.icns` 发布。
