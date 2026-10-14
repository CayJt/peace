# Al-Qur'an app

Flutter client (`mobile_app/`) + FastAPI backend (`backend_server/`). Product spec: [PRD.md](PRD.md).

## Backend
```bash
docker compose up --build                 # energy fallback engine
WITH_WHISPER=1 docker compose up --build  # + faster-whisper (downloads WHISPER_MODEL on first use)
curl localhost:8000/health
```
Env: `ANTHROPIC_API_KEY` (chatbot), `TAJWEED_ENGINE=auto|whisper|energy`, `WHISPER_MODEL` (default `small`).
Without Docker: `cd backend_server && pip install -r requirements.txt && uvicorn main:app --port 8000`.

Score a real recording: `cd backend_server && python -m tools.assess_wav recitation.wav 1:1`.

## Admin console
Roles: `super_admin`, `editor`, `auditor`, `custom` + per-permission RBAC (`analytics.view`, `users.view`, `config.manage`,
`chats.view`, `murajaah.view`, `feedback.manage`, `admins.manage`).

- First start creates Super Admin `admin`. Password = `INITIAL_ADMIN_PASSWORD`, else a temporary one is **printed once** in the
  backend log. Change it in the console. Set `ADMIN_JWT_SECRET` (>= 32 chars) so sessions survive restarts.
- Web: `cd mobile_app && flutter run -d chrome -t lib/admin_main.dart --dart-define=API_BASE=http://localhost:8000`
  Production: `flutter build web -t lib/admin_main.dart --no-web-resources-cdn --dart-define=API_BASE=https://api.example.com`
  (add the console's origin to `CORS_ORIGINS`; localhost origins are allowed by default).
- Mobile app: route `/admin` (debug builds show a Settings entry).
- The reader app uploads heartbeats and scored murajaah session summaries (not audio) so the dashboard/leaderboard have data.

## App
```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE=http://<backend-host>:8000
```
- Android emulator: `10.0.2.2` (default). Phone / iOS simulator: your computer's LAN IP.
- Android minSdk is 24. `http://` is allowed for development only (`usesCleartextTraffic`, iOS ATS):
  remove both and use HTTPS for release.
- Mushaf pages are fetched from Quran.com on first open, then cached in SQLite for offline reading.
- Web is not supported (sqflite).

## Tests
```bash
cd backend_server && pytest
cd mobile_app && flutter analyze && flutter test
QURAN_LIVE=1 flutter test test/integrity/live_api_integrity_test.dart   # real Quran.com data
```
