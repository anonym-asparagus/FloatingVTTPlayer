# Floating VTT Player

[English](README.md) | [简体中文](README.zh-CN.md)

**Download the apps:** [Floating VTT Player website](https://anonym-asparagus.github.io/FloatingVTTPlayer/).

A Windows and macOS audio player for MP3/WAV folders with same-name WebVTT subtitles and a transparent, floating desktop subtitle overlay.

## macOS

The native macOS app is in [`Mac/FloatingVTTPlayerMac.xcodeproj`](Mac/FloatingVTTPlayerMac.xcodeproj).
It requires macOS 14 or later and Xcode 16 or later to build. Open the project in
Xcode and run the `FloatingVTTPlayerMac` scheme, or build from a terminal:

```sh
xcodebuild -project Mac/FloatingVTTPlayerMac.xcodeproj \
  -scheme FloatingVTTPlayerMac -configuration Release \
  -destination 'generic/platform=macOS' build
```

Open **All Files** and use **Add Folder** to import one or more audio folders.
The app remembers folders using security-scoped bookmarks. The player uses a
titlebar-free window with native macOS controls in its upper-left corner.
Select a folder to see
only its tracks; the Tracks area stays empty when no folder is selected. Use
Recently Added, Favorites, personal playlists, and the filename search to find
tracks across folders. The sun/moon button beside search switches between saved
dark and light themes. Playlists start empty until you create one.
Use **Select Folders** in All Files to remove several library entries at once;
the **Remove** button confirms the selected count before removal, and files on
disk remain in place. Use the pencil on a folder card to rename its
library label. Right-click a track to add it to a playlist. The speaker icon
opens a vertical volume control. The expand icon beside it opens a full-window
scrolling subtitle view. The active VTT cue follows playback; click any line to
seek to it. The back chevron returns to the library page you were viewing.
The floating subtitle icon beside the speaker hides or restores the desktop
subtitle window. Press Space in the active player window to pause or resume;
Space still types normally while editing the filename search.

Playback opens the floating subtitle window automatically. Its background is
transparent until you hover over it while unlocked. Locking keeps the background
transparent and hides the appearance and resize controls. The toolbar hides
when the pointer leaves in either mode. Use the subtitle
window's close button to dismiss it, or close the player window to keep playback
available from the menu bar.

To run the parser and matching checks without launching the app:

```sh
swiftc Mac/FloatingVTTPlayerMac/Core.swift Mac/Tests/CoreChecks.swift \
  -o /tmp/floating-vtt-core-checks && /tmp/floating-vtt-core-checks
```

The macOS app stores settings in its own preferences and does not read the
Windows `%APPDATA%` settings file. For distribution outside Xcode, sign and
notarize the macOS app with your Apple Developer identity.

## Windows

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
