# FieldPulse Mobile

Flutter 3.47 Android client for FieldPulse. The app is local-first: attendance, GPS points, privacy acknowledgement and sync intent are persisted before network operations.

## Implemented foundation

- Secure token + installation UUID storage
- Central URL normalization and device headers
- SQLite v4 with additive migration path, outbox, local sessions and GPS points
- Local-first Start Day / End Day with attendance outbox
- Dedicated GPS uploader with stable client UUIDs and per-point verdict mapping
- Foreground-service location stream during active sessions only
- Privacy disclosure and local-first acknowledgement
- Tenant tracking policy cache with safe manual fallback
- Tenant timezone database initialized at startup
- Session restore, logout stop, local history and modern Material 3 UI

## Run against the local web project

Start `field-sales-web` on port 8001, then:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001/api/v1
```

For a physical Android phone, replace `10.0.2.2` with your computer's LAN IP and ensure the firewall allows port 8001.

Demo login after running the web seeder:

- `salesman@example.com`
- `password`

## Verify

```bash
dart format lib test
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8001/api/v1
git diff --check
```

## Production Android releases

Production builds are HTTPS-only, require external release signing credentials, and are verified in CI with a signed release AAB smoke build. Real release keys are never stored in the repository.

See [RELEASE.md](RELEASE.md) for signing setup, GitHub Actions secrets/variables, versioning, artifact checksums, and the release checklist.


## Production endpoint

The canonical FieldPulse production backend is `https://fieldpulse.businessos.af`. Production Android releases must be built with `PRODUCTION_API_BASE_URL=https://fieldpulse.businessos.af/api/v1`. Debug/local builds remain configurable independently through `API_BASE_URL`.
