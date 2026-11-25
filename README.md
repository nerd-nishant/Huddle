# HUDDLE

Campus app: organised private chats, QR + location attendance, official/unofficial
updates, fest channels, and offline handwritten-style notes.
Flutter (Android) + Supabase (Postgres, Auth, Realtime, Storage) + SQLite.

## Get the APK (no installs on your PC)

1. **Supabase** (free): create a project at supabase.com.
   - SQL Editor: run `supabase/schema.sql`, then `supabase/seed_dev.sql` (sample data).
   - Authentication > Providers > Email: for easy testing turn **off** "Confirm email".
   - Project Settings > API: copy the **Project URL** and **anon public key**.
2. **GitHub**: create a repo, upload this whole folder (keep `.github/`).
   - Repo > Settings > Secrets and variables > Actions > add
     `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. Repo > **Actions > Build HUDDLE APK > Run workflow**. After ~8 min, download the
   `HUDDLE-apk` artifact, unzip, install `app-release.apk` on your phone
   (allow "install unknown apps").

Or build locally: `flutter create --platforms=android .`, `python3 tools/patch_manifest.py`,
`./tools/fetch_fonts.sh`, then
`flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

## First run checklist

| Who | How |
|---|---|
| Student | Sign up in the app (role Student, pick the seeded college/dept, Sem 5, batch A). Auto-joins groups + subjects. |
| Teacher | Sign up as Teacher. Approve + assign subjects with the SQL at the bottom of `seed_dev.sql`. |
| Institution (official notices) | Sign up, then promote with the SQL in `seed_dev.sql`. Not creatable from the app by design. |
| Fest organiser | Promote in `group_members` (SQL in seed file). |

## How the QR attendance is secured

1. Teacher taps **Start lecture**: phone location is saved as the classroom centre with a radius.
2. QR = `huddle://att?s=<session>&t=<token>`; the token **rotates every 20 s** (old one valid 30 s).
3. Student must scan **inside the HUDDLE app** (other scanners just see a `huddle://` link), signed in, enrolled.
4. App sends GPS to `mark_attendance_qr`; **the server** re-checks token freshness, enrolment, session open and distance (haversine). Mock-location is rejected on the device.
5. Students have **no write access** to attendance tables (RLS). Every change lands in `attendance_audit`.

Honest limits: a QR cannot cryptographically prove "only this app scanned it" - the server checks
(login + fresh token + GPS) are what enforce it. GPS can be spoofed on rooted phones; for stricter
needs add Play Integrity attestation or Wi-Fi/BLE beacons.

## Things that need external services (not faked)

- **Phone-number login / OTP**: needs an SMS provider in Supabase. Email login is used; phone is never collected.
- **Official-notice accounts & teacher approval**: manual admin step in Supabase (by design = verification).
- **Real enrolment data**: `claim_my_groups()` auto-enrols by dept+semester for demos only. Import from your registrar for production.
- **Push notifications**: not included (needs Firebase).
- **On-device LLM**: see below.

## Offline notes: what it is and isn't

The notes generator runs entirely on the phone using a built-in **extractive summariser** (`lib/study/notes_engine.dart`):
detects headings, ranks sentences by topic importance, removes repetition, keeps definitions and formulas verbatim,
trims filler, highlights keywords, and renders paged ruled-paper notes in a handwriting font.
It is **not** a generative LLM: it selects and tightens your sentences, it doesn't rewrite them in new words.
To add a real local model, plug a runtime such as `flutter_gemma` (Gemma 2B/3 1B, ~0.5-1.5 GB download) or
`llama.cpp` bindings into `generateNotesJson` and feed its output into the same `GeneratedNotes` structure.
Input is paste or `.txt/.md`; PDF/photo OCR is not included.

## Project map

```
lib/core        theme, supabase helpers, shared widgets, sqlite
lib/auth        login / register
lib/shell       5-tab navigation, Home, profile
lib/chats       organised groups, chat room, fest channels
lib/attendance  student dashboard, QR scanner, teacher live session
lib/updates     official vs unofficial feeds
lib/study       notes engine, handwritten viewer, offline library
supabase/       schema.sql (tables, RLS, RPCs), seed_dev.sql
```
