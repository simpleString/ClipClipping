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
.\build\bin\Release\ClipClipping.exe
```

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
.\build\bin\Release\ClipClipping.exe
```

If your generator is single-config, executable path may be:

```powershell
.\build\bin\ClipClipping.exe
```

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

- `ClipClipping-vX.Y.Z-linux-portable.tar.gz`
- `ClipClipping-vX.Y.Z-windows-portable.zip`

Both bundles include `ffmpeg` and `ffprobe` in the `tools/` directory.

## Current scope

- Video selection (dialog + drag&drop)
- Playback via Qt Multimedia
- Trim range (start/end)
- GIF export with auto quality fallback to fit under 10MB
- Progress + cancel

No mpv fallback yet (intentionally disabled for this stage).
