# Quran App — Product Requirements Document (Single Source of Truth)

Stack: Flutter (Mobile/Web) · FastAPI (Python 3.11) · Docker Compose · Google Stitch MCP · SQLite · WebSockets · Quran.com API v4 · Whisper STT

## 1. Executive Summary & Design Vision

A production-ready, distraction-free Holy Quran app with real-time Tajweed speech assessment.

- **Canvas:** minimalist; Paper Warm `#FAF8F5` (light) and OLED Dark `#121212` (dark). No gradients, ads or badges on the reading surface.
- **Layout:** authentic Madinah Mushaf, 604 pages, 15 lines per page.
- **Principle:** zero visual clutter. Controls appear on demand and hide while reading.
- **Design source:** Google Stitch project tokens (colors, type, spacing) are mapped into `mobile_app/lib/theme/app_theme.dart`.

## 2. Authentication & Account Management

### 2.1 Login
- Username + password.
- Quick biometric / fingerprint sign-in via `local_auth`. Credentials/tokens are held in `flutter_secure_storage`.
- Fallback to password when biometrics are unavailable or fail.

### 2.2 Registration
- Fields: Email, Full Name, Password, Password confirmation.
- Validation: email format, password strength, confirmation match. Inline errors.

### 2.3 Settings
- User profile (name, email) and **Khatam badge** (completed cycles).
- Reading-time notification settings (time picker, on/off).
- Theme switch (Light / Dark / System).
- Destructive **Logout** button (red, with confirmation dialog); clears secure storage.

## 3. Core Reading & Mushaf Engine

- Authentic 604-page Uthmanic Madinah layout; fully justified Arabic text.
- Circular ayah-end markers, Surah banners, Juz headers/footers.
- **Smart Floating Action Capsule:** glassmorphism, auto-hides on downward scroll, reappears on upward scroll.
- Quick toggles in the capsule:
  1. Tajweed rule colors ↔ monochrome
  2. Indonesian translation (Quran.com Resource ID **33**)
  3. Tahfidz masking mode (hide words, reveal on tap/recitation)
  4. Live mic speech scoring
  5. Dynamic score chip (running score of current page/ayah)

## 4. Backend & Real-Time Tajweed Evaluation

### 4.1 WebSocket `/ws/assess-tajweed/{verse_key}`
- Client streams **16 kHz mono 16-bit PCM** frames.
- Server pipeline: buffer → Whisper STT → alignment against the reference verse → per-phoneme/letter Tajweed evaluation.
- Server emits live events, e.g. `{"event":"LETTER_ASSESSED","verse_key":"1:1","index":3,"letter":"ب","score":0.92,"rule":"qalqalah"}`.
- Final `VERSE_SUMMARY` event with aggregate score.

### 4.2 Quran AI Chatbot `POST /api/v1/quran-chat`
- Strict guardrails: answers only within the Quranic domain (tafsir, meaning, tajweed, recitation, Islamic reading context). Off-domain prompts get a fixed refusal.
- Answers cite verse keys; no fabricated verses (verse text is always fetched from verified data).

### 4.3 Other
- `GET /health` → `{"status":"ok","service":"quran_backend"}`.
- SQLite for users, history, scores. Secrets via environment only.

## 5. Gamification, History & Notifications

- Daily and weekly reading history charts (`fl_chart`).
- Summary: average score, evaluated-letters count.
- **Khatam tracker:** +10 pts per page read for ≥30 s; cycle counter increments on reaching page 604.
- Daily adaptive notifications (`flutter_local_notifications` + `timezone`) with contextual Quranic snippets, scheduled at the user's reading time.

## 6. Data Integrity & Verification Standard

- 100% exact match against Quran.com API v4: zero diacritic loss, zero truncation, correct word count, correct letter decomposition.
- Automated verification test fetches every verse and asserts byte-equal text, word counts and per-verse letter counts; CI fails on any mismatch.
- Text is never normalized or re-encoded on the way to display.

## 7. Architecture & Containerization

```
/
├── PRD.md
├── docker-compose.yml        # backend (+ optional web)
├── .github/workflows/ci.yml  # pytest + flutter test
├── backend_server/           # FastAPI, Python 3.11 (Dockerfile, main.py, tests/)
└── mobile_app/               # Flutter client (BLoC, sqflite, theme/app_theme.dart)
```

- Docker Compose: `backend` (build `./backend_server`, container `quran_backend`, port `8000:8000`, volume `./backend_server:/app`).
- Optional `web` service: Flutter web build served by Nginx (added in a later phase).
- Client architecture: `flutter_bloc` + `equatable`; local data in `sqflite`; secrets in `flutter_secure_storage`; preferences in `shared_preferences`.

## 8. Roadmap

- **FASE 1:** Docker, backend skeleton, Flutter workspace, CI.
- **FASE 2:** Google Stitch inspection and mapping to `app_theme.dart`.
- Later: Mushaf engine, auth, WebSocket assessment, chatbot, gamification, data-integrity suite.
