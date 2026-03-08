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

## Validation and Release

The release workflow uses three commands:

```bash
./scripts/build-local
./scripts/build-prod
./scripts/prod-deploy
```

`./scripts/build-local` runs `swift test` and builds a local DMG at `dist/Whisper-Anywhere-test.dmg`.

To build a signed production DMG, run:

```bash
./scripts/build-prod
```

This creates a signed + notarized versioned DMG in `dist/` and copies that versioned DMG into `website/downloads/`.

To publish the current release to Vercel, run:

```bash
./scripts/prod-deploy
```

This updates the website download links to the selected versioned DMG, deploys the website, and verifies the live site serves that version.

Local enforcement:

```bash
./scripts/setup_git_hooks.sh
```

This configures the repository hook path. The `pre-push` hook is intentionally a no-op; this project does not run builds automatically from git hooks.
