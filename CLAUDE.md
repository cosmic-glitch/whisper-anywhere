# Whisper Anywhere

macOS menu bar app for system-wide dictation using OpenAI Whisper. Built with Swift Package Manager.

## Release

Only three release commands are allowed:

1. `build local` -> `./scripts/build-local`
2. `build prod` -> `./scripts/build-prod`
3. `prod deploy` -> `./scripts/prod-deploy`

Rules:
- Do not run build or deploy commands automatically from hooks or because app files changed.
- `build prod` is the only command that creates a production DMG.
- `prod deploy` is the only command that publishes the website and release assets to Vercel.
- Versioning, notarization, and website-link updates are owned by the scripts, not duplicated in this file.
