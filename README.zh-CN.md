# Floating VTT Player

[English](README.md) | [简体中文](README.zh-CN.md)

**直接下载 Windows 版：**[Floating VTT Player 官网](https://anonym-asparagus.github.io/FloatingVTTPlayer/)。无需安装 .NET，也不用自行编译。macOS 版本将在之后推出。

一款 Windows 音频播放器，可播放文件夹中的 MP3/WAV 文件，并显示与音频文件同名的 WebVTT 字幕。字幕显示在透明、始终置顶的桌面悬浮窗中。

在 Windows 上构建本项目需要 .NET 8 SDK。发布的 Windows x64 可执行文件是自包含版本，运行时无需另行安装 .NET 运行时。

## 音频与字幕文件

将字幕文件放在对应音频文件旁边，并使用相同的基本文件名：

```text
01.wav
01.vtt
02.mp3
02.vtt
```

匹配器也支持双重扩展名和文件名中的标点差异，例如：

```text
01_Night-Ride.wav
01_Night-Ride.wav.vtt
```

匹配顺序依次为：完整文件名精确匹配、基本文件名精确匹配、忽略标点的文件名匹配，最后按对应的阿拉伯数字曲目编号匹配。每个 VTT 文件只会分配给一个音频曲目。

## 操作说明

- 点击 **Browse folder**（浏览文件夹）扫描文件夹，并按自然顺序生成播放列表。
- 双击曲目或点击 **Play**（播放）开始播放。
- 当前曲目播放完毕后，自动播放下一首。
- 将鼠标移到字幕悬浮窗上，可显示播放/暂停、锁定/解锁、关闭和外观控制按钮。
- 解锁悬浮窗后，可以拖动或调整其大小，并修改字体和字号。点击颜色与阴影图标可打开相应设置，工具栏不会被文字标签挤占。
- 较长的字幕会根据悬浮窗宽度自动换行；必要时悬浮窗会增高，使工具栏始终位于字幕上方。
- 锁定后会保留悬浮窗位置并隐藏编辑控件；将鼠标移上去并点击锁定图标即可再次编辑。
- 可以通过悬浮窗右上角的 **×**、主窗口或系统托盘菜单显示/隐藏字幕，而不会停止音频播放。
- 关闭播放器主窗口时，程序会缩到系统托盘；可通过托盘菜单重新打开或退出。

## 构建与运行

```powershell
dotnet restore
dotnet run --configuration Release
```

生成体积较小、可独立运行的 Windows x64 可执行文件：

```powershell
dotnet publish --configuration Release -p:PublishProfile=Lightweight --output publish-light
```

生成的 `publish-light\FloatingVttPlayer.exe` 是单文件自包含程序。发布配置会压缩内嵌的 .NET 程序集，并将 WPF 原生库一并打包进可执行文件，以缩小文件体积。启动时解压程序集可能会稍微增加启动时间；应用代码、功能和视觉资源均未删减。

程序设置保存在 `%APPDATA%\FloatingVttPlayer\settings.json`。

Git 仓库不会收录发布后的可执行文件。如需分发程序，请将构建产物附加到 GitHub Releases。
