# ClipClipping

Qt 6 + QML app for creating short clips and GIFs (MVP).

## Quick Start (Linux)

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/ClipClipping
```

## Quick Start (Windows)

```powershell
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
cmake --install build --config Release --prefix package
windeployqt --release --qmldir .\src .\package\bin\ClipClipping.exe
.\package\bin\ClipClipping.exe
```

Windows build requires Qt runtime deployment (DLLs, plugins, QML modules).
Running `build\...\ClipClipping.exe` directly will usually fail with missing `Qt6*.dll` errors.

For portable usage, place FFmpeg tools into:

- `package\tools\ffmpeg.exe`
- `package\tools\ffprobe.exe`

## Dependencies

- Qt 6.5+ (Core, Gui, Quick, QuickControls2, Multimedia, Concurrent)
- `ffmpeg`
- `ffprobe` (usually shipped with ffmpeg)

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

## Run

```bash
./build/bin/ClipClipping
```

## Local build (Windows)

```powershell
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
cmake --install build --config Release --prefix package
windeployqt --release --qmldir .\src .\package\bin\ClipClipping.exe
.\package\bin\ClipClipping.exe
```

If `windeployqt` is not found, use Qt Command Prompt or full path to `windeployqt.exe`
(for example `C:\Qt\6.x.x\msvc2019_64\bin\windeployqt.exe`).

If your generator is single-config, build output executable path may be:

```powershell
.\build\bin\ClipClipping.exe
```

but it should still be launched from deployed `package\bin\ClipClipping.exe`.

## Portable package (local)

```bash
cmake --install build --config Release --prefix package
```

Add FFmpeg tools manually into `package/tools`:

- Linux: `package/tools/ffmpeg`, `package/tools/ffprobe`
- Windows: `package/tools/ffmpeg.exe`, `package/tools/ffprobe.exe`

## CI/CD (GitHub Actions)

- `build.yml`: builds portable Linux/Windows bundles on every push/PR and uploads artifacts.
- `release.yml`: on tag `v*` builds portable bundles and publishes them to GitHub Releases.

### Release a new version

```bash
git tag v1.0.0
git push origin v1.0.0
```

After that, release assets are generated automatically:

- `ClipClipping-vX.Y.Z-linux-x86_64.AppImage`
- `ClipClipping-vX.Y.Z-windows-portable.zip`

Linux AppImage and Windows bundle include `ffmpeg` and `ffprobe`.

Run AppImage:

```bash
chmod +x ClipClipping-vX.Y.Z-linux-x86_64.AppImage
./ClipClipping-vX.Y.Z-linux-x86_64.AppImage
```

Local AppImage build helper:

```bash
./scripts/build-appimage.sh
```

Output file:

- `dist/ClipClipping-local-x86_64.AppImage`

Script tries `ffmpeg`/`ffprobe` from `PATH` first.
If they are missing, it downloads a static Linux build automatically into `.cache/ffmpeg`.
It also downloads AppImage tooling (`linuxdeploy`, `appimagetool`) into `.cache/appimage-tools`.

Optionally you can override tool paths:

```bash
FFMPEG_BIN=/usr/bin/ffmpeg FFPROBE_BIN=/usr/bin/ffprobe ./scripts/build-appimage.sh
```

Note for AppImage runtime:

- It defaults to `xcb` platform for better compatibility.
- File picker in AppImage uses Qt dialog (not native DE dialog) to avoid KDE/KIO runtime issues.

## Current scope

- Video selection (dialog + drag&drop)
- Playback via Qt Multimedia
- Trim range (start/end)
- GIF export with auto quality fallback to fit under 10MB
- Progress + cancel

No mpv fallback yet (intentionally disabled for this stage).
