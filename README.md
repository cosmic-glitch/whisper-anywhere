# Whisper Anywhere

Native macOS menu bar app for system-wide dictation. Hold `Fn` to record, release to transcribe, and text is inserted at the active cursor. Download at [whisperanywhere.app](https://whisperanywhere.app).

## Features

- **Fn hold-to-talk** across any macOS app
- **OpenAI** transcription (`gpt-4o-mini-transcribe`) or **Deepgram** streaming transcription
- **Edit mode** — select text before recording and speak an edit command; Whisper Anywhere rewrites the selection using GPT
- Direct text insertion via Accessibility with clipboard fallback
- Menu bar UI with recording/transcribing HUD and permission guidance

## Install

Download the latest release from [whisperanywhere.app](https://whisperanywhere.app). Requires macOS 14+ with Microphone, Accessibility, and Input Monitoring permissions.

## Development

Build and install a local dev build:

```bash
./scripts/install_app.sh
```

Run tests:

```bash
swift test
```

## Release

Three commands, run manually (never from hooks):

```bash
./scripts/build-local      # swift test + local DMG at dist/Whisper-Anywhere-test.dmg
./scripts/build-prod       # signed + notarized production DMG in dist/ and website/downloads/
./scripts/prod-deploy      # deploy website and release assets to Vercel
```

## Backend (Vercel + Supabase)

The website at [whisperanywhere.app](https://whisperanywhere.app) is deployed to Vercel. The backend handles authentication and key distribution — users sign in with Google, and the app fetches API keys from the backend to call OpenAI and Deepgram directly.

API routes under `website/api/`:

- `POST /api/auth/google/start` — return a Supabase Google OAuth URL
- `POST /api/auth/google/session` — validate token and sync user profile/device
- `POST /api/auth/refresh` — refresh session tokens
- `POST /api/auth/apikey` — retrieve the server's OpenAI API key (authenticated)
- `POST /api/auth/deepgram-apikey` — retrieve the server's Deepgram API key (authenticated)

Supabase tables: `profiles`, `devices`. Bootstrap SQL at [`website/supabase-schema.sql`](website/supabase-schema.sql).
