# Repository Agent Rules

## Mandatory Release Rule

For any change to app/runtime code, do a full release pipeline before push.

## Rebuild Semantics (Signed Release)

When asked to "rebuild" release artifacts, treat it as a full signed release:

1. Run `./scripts/release_dmg.sh` with:
   - `--identity "Developer ID Application: ..."`
   - `--notary-profile ...`
   - explicit `--version` and `--build-number`
2. Do **not** use `--skip-notarize` unless explicitly requested.
3. Ensure both artifacts are produced in `dist/`:
   - `Whisper-Anywhere-<version>.dmg` (signed + notarized + stapled)
   - `Whisper Anywhere-<version>.zip` (notarization submission bundle)
4. Copy the new versioned DMG to `website/downloads/`.
5. Update website download links to the new versioned DMG when shipping that rebuild.

### Trigger paths
- `WhisperAnywhere/**`
- `WhisperAnywhereTests/**`
- `Package.swift`

### Required steps
1. Run `./scripts/full_release.sh`.
2. Ensure both artifacts are updated in git:
   - `dist/Whisper-Anywhere-unsigned.dmg`
   - `website/downloads/Whisper-Anywhere-unsigned.dmg`
3. Ensure both DMGs are byte-identical (same SHA-256).

### Do not push if
- only one DMG path was updated
- DMG hashes do not match
