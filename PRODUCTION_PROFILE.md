# FieldPulse Android Production Profile

Canonical backend:

```text
https://fieldpulse.businessos.af
```

Canonical API base URL:

```text
https://fieldpulse.businessos.af/api/v1
```

Before running the production Android release workflow, configure the GitHub Actions repository variable:

```text
PRODUCTION_API_BASE_URL=https://fieldpulse.businessos.af/api/v1
```

and the four external signing secrets documented in `RELEASE.md`.

The workflow must continue to fail closed when either the API variable or signing inputs are missing. Do not commit a keystore, password, token, or production secret.

A successful CI-signed AAB is build evidence only. Batch 19 requires the real externally signed RC APK to be installed on a physical Android device and UAT evidence to be recorded in `UAT_RESULTS_TEMPLATE.md`.
