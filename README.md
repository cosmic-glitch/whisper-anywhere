# Native Whisper

Native Whisper is a simple push-to-talk dictation app for macOS.
Hold `Fn` to speak. Release `Fn` to transcribe. Your text appears at the cursor.

## Why it is useful

- Fast dictation without a full app window
- Clear recording feedback with a chime and compact HUD
- One-key interaction you can use across apps
- No post-editing or rewriting of your words

## What it does

- Runs as a native menu bar app on macOS 14+
- Starts recording while `Fn` is held
- Shows live audio bars while recording
- Shows `Transcribing` status after release
- Sends audio to OpenAI `whisper-1` with `language=en`
- Inserts transcript into the focused text field
- Falls back to clipboard if no editable target is focused

## Requirements

- macOS 14+
- `OPENAI_API_KEY`
- Microphone permission
- Accessibility permission
- Input Monitoring permission

## Quick Start

1. Add your API key to a `.env` file in the repo root:

```bash
OPENAI_API_KEY=your_key_here
```

2. Install and launch:

```bash
./scripts/install_app.sh
```

This script builds the app, installs it to `/Applications/NativeWhisper.app`,
stops any existing Native Whisper process, and relaunches the latest build.

3. Grant permissions when prompted (or from System Settings).

4. Place the cursor in any text field, hold `Fn`, speak, and release `Fn`.

## Run From Terminal (Optional)

```bash
export OPENAI_API_KEY="your_key_here"
swift run NativeWhisper
```

## Test

```bash
swift test
```
