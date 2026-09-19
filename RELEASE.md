# Android Production Release

Stage 2 Batch 18 establishes a repeatable, secret-backed Android release path for Field Sales.

## Release invariants

Production Android builds must satisfy all of the following:

- The API base URL is explicitly supplied at build time.
- The production API URL uses HTTPS and ends with `/api/v1`.
- `APP_VERSION` is supplied to Dart and matches the release version.
- Android cleartext traffic is disabled in the main/release manifest.
- A release keystore is provided outside the repository.
- AAB/APK artifacts are signed with the configured upload key.
- The committed `pubspec.lock` is used for deterministic dependencies.
- The Git tag, when used, matches `v<pubspec version name>`.

Debug builds keep a separate manifest override so emulator/LAN HTTP development remains available.

## Versioning

The canonical mobile version is the `version:` field in `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

- `1.0.0` is Android `versionName` and the Dart `APP_VERSION` sent to the API.
- `1` is Android `versionCode`.
- Increase `versionCode` for every Android release.
- Update `versionName` when the public application version changes.

For a tagged release, use a tag matching the version name, for example `v1.0.0`.

## Local signed release

Create an Android upload keystore outside the repository. One example:

```bash
keytool -genkeypair -v \
  -keystore /secure/path/field-sales-upload.jks \
  -alias field-sales-upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Copy the template:

```bash
cp android/key.properties.example android/key.properties
```

Then replace every placeholder. `android/key.properties` and common keystore extensions are Git-ignored.

Build:

```bash
flutter pub get --enforce-lockfile

flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://YOUR_DOMAIN/api/v1 \
  --dart-define=APP_VERSION=1.0.0

flutter build apk --release \
  --dart-define=API_BASE_URL=https://YOUR_DOMAIN/api/v1 \
  --dart-define=APP_VERSION=1.0.0
```

A release Gradle task fails if signing configuration is absent. A production-mode app also fails closed during startup if the API URL/version defines are absent or if the API URL is not HTTPS.

## GitHub production release workflow

`.github/workflows/android-release.yml` supports:

- manual `workflow_dispatch`
- Git tags matching `v*`

Configure the following GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Configure this GitHub Actions repository variable:

- `PRODUCTION_API_BASE_URL` — for example `https://sales.example.com/api/v1`

Generate the base64 keystore value without adding the keystore to Git:

```bash
base64 -w 0 /secure/path/field-sales-upload.jks
```

On macOS, use:

```bash
base64 < /secure/path/field-sales-upload.jks | tr -d '\n'
```

Store only the resulting value in the GitHub secret.

The workflow validates configuration, restores the keystore only inside the runner, runs formatting/analyze/tests, builds the signed AAB and APK, calculates SHA-256 checksums, and uploads the artifacts. The keystore itself is never uploaded as an artifact.

## CI release proof

Normal `mobile-ci` creates a one-day throwaway keystore and builds a signed release AAB against an invalid-but-HTTPS CI URL. This proves:

- the release Gradle task compiles
- signing configuration is wired correctly
- production Dart defines are required and accepted
- cleartext production configuration does not break compilation

The ephemeral CI key is not a distribution key and must never be used for real releases.

## Distribution

For Google Play, upload the signed `app-release.aab` and use Play App Signing with this repository's key acting as the upload key.

For controlled direct distribution, use the signed `app-release.apk`. Preserve its `SHA256SUMS.txt` alongside the APK so recipients can verify the artifact.

## Release checklist

Before promoting an Android artifact:

1. Confirm the backend production `/ready` endpoint is healthy.
2. Confirm `PRODUCTION_API_BASE_URL` points to that HTTPS deployment and ends with `/api/v1`.
3. Increment `pubspec.yaml` version/versionCode as required.
4. Regenerate and commit `pubspec.lock` only when dependencies intentionally change.
5. Run mobile CI and require all gates green.
6. Build with the production workflow.
7. Verify artifact checksums.
8. Install the signed APK on a real Android device.
9. Run Batch 19 release-candidate/UAT golden paths, especially offline sync and background GPS.
10. Do not publish/promote until the approved production icon/splash/branding is present.

## Branding blocker

The repository currently has no approved Field Sales icon/splash asset and the Android manifest still references the platform default icon. The release pipeline is production-capable, but Batch 19 must treat approved branding as a launch blocker rather than shipping the default system icon.
