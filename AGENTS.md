# Repository Agent Rules

## Mandatory Release Rule

For any change to app/runtime code, do a full release pipeline before push.

### Trigger paths
- `NativeWhisper/**`
- `NativeWhisperTests/**`
- `Package.swift`
- `scripts/install_app.sh`
- `scripts/release_dmg.sh`

### Required steps
1. Run `./scripts/full_release.sh`.
2. Ensure both artifacts are updated in git:
   - `dist/Whisper-Anywhere-unsigned.dmg`
   - `website/downloads/Whisper-Anywhere-unsigned.dmg`
3. Ensure both DMGs are byte-identical (same SHA-256).

### Do not push if
- only one DMG path was updated
- DMG hashes do not match
