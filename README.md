# Floating VTT Player

[English](README.md) | [简体中文](README.zh-CN.md)

**Download the ready-to-run Windows app:** [Floating VTT Player website](https://anonym-asparagus.github.io/FloatingVTTPlayer/). No .NET installation or build tools are needed. A macOS version is planned.

A Windows audio player for MP3/WAV folders with same-name WebVTT subtitles and a transparent, always-on-top desktop subtitle overlay.

Builds require the .NET 8 SDK on Windows. The published Windows x64 executable is
self-contained and does not require a separate .NET runtime installation.

## File layout

Keep each subtitle beside its corresponding audio file and give it the same base name:

```text
01.wav
01.vtt
02.mp3
02.vtt
```

The matcher also supports double extensions and punctuation differences:

```text
01_Night-Ride.wav
01_Night-Ride.wav.vtt
```

Matching order is: exact full filename, exact base name, punctuation-insensitive name,
then corresponding Arabic track numbers. A VTT file is assigned to only one audio track.

## Controls

- **Browse folder** scans the selected folder and builds a naturally sorted playlist.
- Double-click a track, or press **Play**, to start playback.
- Playback automatically advances to the next track.
- Hover over the subtitle to reveal play/pause, lock/unlock, close, and appearance controls.
- Unlock the overlay to drag or resize it and edit font and text size. The color
  and shadow icons open their controls without crowding the toolbar.
- Long subtitle lines wrap to the current overlay width, and the overlay grows
  when needed to keep the toolbar above the text.
- Locking preserves the overlay position and hides editing controls; hover and click the lock icon to edit again.
- Use the overlay's **×** button, the main window, or the tray menu to show/hide subtitles without stopping audio.
- Closing the control window hides it to the notification area. Use the tray menu to restore or exit.

## Build and run

```powershell
dotnet restore
dotnet run --configuration Release
```

To create the compact, standalone Windows x64 executable:

```powershell
dotnet publish --configuration Release -p:PublishProfile=Lightweight --output publish-light
```

The resulting `publish-light\FloatingVttPlayer.exe` is a self-contained single file.
The publish profile compresses embedded .NET assemblies and includes native WPF
libraries in the executable. This reduces download size but may add a little
startup time while assemblies are decompressed. No application code, features,
or visual assets are removed.

The application settings are stored in `%APPDATA%\FloatingVttPlayer\settings.json`.

Published executables are excluded from Git. Attach builds to GitHub Releases
when distributing the app.
