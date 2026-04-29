# telegramGifterQt

Qt 6 + QML port of Telegram GIF Maker (MVP).

## Dependencies

- Qt 6.5+ (Core, Gui, Quick, QuickControls2, Multimedia, Concurrent)
- `ffmpeg`
- `ffprobe` (usually shipped with ffmpeg)

## Build

```bash
cmake -S . -B build
cmake --build build -j
```

## Run

```bash
./build/telegramGifterQt
```

## Current scope

- Video selection (dialog + drag&drop)
- Playback via Qt Multimedia
- Trim range (start/end)
- GIF export with auto quality fallback to fit under 10MB
- Progress + cancel

No mpv fallback yet (intentionally disabled for this stage).
