# Whisper Anywhere

Whisper Anywhere is a native macOS push-to-talk dictation app.
Hold `Fn` to record, release `Fn` to transcribe, and text is inserted at the active cursor.

## What users get

- Fn hold-to-talk across macOS apps
- On-device recording with immediate upload on release
- OpenAI transcription (`gpt-4o-mini-transcribe`, English only)
- Direct text insertion with clipboard fallback when no cursor is focused
- Menu bar UX with recording/transcribing HUD and permission guidance

## Transcription path

Whisper Anywhere is now direct-only:

- `Direct OpenAI`: use your own OpenAI key and call OpenAI directly from the app.

No hosted proxy path or sign-in flow is used by the macOS app.

## Requirements

- macOS 14+
- Microphone permission
- Accessibility permission
- Input Monitoring permission

## App local environment

Create `.env` in repo root (or export these variables before launch):

```bash
OPENAI_API_KEY=your_key_here
```

## Install and run app

```bash
./scripts/install_app.sh
```

This builds and installs `/Applications/Whisper Anywhere.app`, terminates any running instance, and relaunches the latest build.

## Backend (Vercel + Supabase)

API routes are implemented under `website/api`:

- `POST /api/auth/google/start`
- `POST /api/auth/google/session`
- `POST /api/auth/refresh`
- `POST /api/transcribe`
- `GET /api/quota`

Configure these Vercel environment variables:

- `OPENAI_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_AUTH_REDIRECT_URI`
- `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` (for `supabase config push`)
- `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET` (for `supabase config push`)
- `APP_TRANSCRIPTION_ENABLED`
- `DEVICE_DAILY_TRANSCRIPTION_CAP`
- `MAX_UPLOAD_BYTES`
- `GLOBAL_DAILY_ESTIMATED_USD_CAP`
- `ESTIMATED_USD_PER_AUDIO_MINUTE`
- `AUTH_START_IP_WINDOW_SECONDS`
- `AUTH_START_IP_LIMIT`
- `TX_IP_WINDOW_SECONDS`
- `TX_IP_LIMIT`
- `TX_USER_WINDOW_SECONDS`
- `TX_USER_LIMIT`
- `TX_DEVICE_WINDOW_SECONDS`
- `TX_DEVICE_LIMIT`

The website and backend routes are optional for app distribution and hosted experiments.

Supabase tables expected by backend:

- `profiles`
- `devices` (unique `(user_id, device_id)`)
- `usage_ledger`
- `budget_state`

Bootstrap SQL is provided at [`website/supabase-schema.sql`](website/supabase-schema.sql).

## Test

```bash
swift test
```

## Full Release Pipeline (Required)

For any app/runtime code change, always run:

```bash
./scripts/full_release.sh
```

This command:

- runs tests
- rebuilds `dist/Whisper-Anywhere-unsigned.dmg`
- updates `website/downloads/Whisper-Anywhere-unsigned.dmg`
- verifies both DMG files are byte-identical (SHA-256 match)

Local enforcement:

```bash
./scripts/setup_git_hooks.sh
```

This installs a `pre-push` guard that blocks pushes if app code changed without both DMGs being updated and matching.
