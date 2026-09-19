# Field Sales Android — Release Candidate UAT

Use this checklist only with a signed release-candidate APK built for the staging/UAT HTTPS API. Record actual evidence; do not mark an item passed from unit-test results alone.

## Before the device test

Record:

- Web SHA:
- Mobile SHA:
- App version:
- Android version:
- Device manufacturer/model:
- UAT tenant:
- UAT tester:
- UTC start time:

Confirm:

- staging `/ready` returns healthy
- queue workers and scheduler are running
- UAT tenant/master data is prepared
- release APK signature/checksum is recorded
- approved production icon/splash is present

If the default Android application icon is still present, stop and mark UAT-01 **BLOCKED**.

## UAT-01 — Clean install and launch

1. Remove any previous Field Sales install.
2. Install the signed RC APK.
3. Launch it from the Android launcher.
4. Confirm the expected app name/icon/splash.
5. Confirm no emulator/local/debug URL appears anywhere.

Expected: clean launch with production branding and no debug configuration exposure.

## UAT-02 — Login and device binding

1. Sign in with the UAT salesman.
2. Verify tenant, salesman identity and expected permissions.
3. Sign out and sign in again on the same installation.
4. Attempt to register a second active device for the same salesman.

Expected: same device is reusable; second active device is rejected according to policy.

## UAT-03 — Privacy and permissions

Exercise the Android location, background-location and notification permission path.

Expected:

- disclosure appears before tracking behavior that requires it
- denial does not crash the app
- granting permissions permits the intended tracking flow
- privacy acknowledgement is retained

Record the exact Android permission choices.

## UAT-04 — Start Day and online GPS

1. Start Day while online.
2. Confirm active session is visible locally.
3. Move enough for multiple valid GPS updates.
4. Confirm admin live map/current-location data updates.

Expected: one active work session, ordered GPS updates, no duplicate sessions.

## UAT-05 — Full offline field workflow

Enable airplane mode, then:

1. Check in to a customer.
2. Add visit notes.
3. Capture/add a visit photo if available in the current UI.
4. Check out the visit.
5. Create a credit order.
6. Create a collection.
7. Create an expense.
8. Continue moving long enough to generate offline GPS points.
9. End Day if the intended workflow permits ending while offline.

Expected: every action remains usable and visibly pending; no network error destroys local work.

## UAT-06 — Process restart while offline

1. Force-stop the app.
2. Relaunch it while still offline.
3. Inspect visit/order/collection/expense/session state.

Expected: all locally persisted work remains present exactly once with correct values and pending state.

## UAT-07 — Reconnect and synchronize

1. Restore network connectivity.
2. Trigger/allow synchronization.
3. Observe sync-health UI/state.
4. Repeat sync once more after success.

Expected:

- attendance dependencies synchronize before GPS/visits
- orders/collections/expenses synchronize without duplicates
- second sync is safe/idempotent
- blocked/non-retryable failures are visible rather than looping forever

## UAT-08 — Admin review round-trip

From the web admin:

1. Approve the synced order.
2. Verify the collection.
3. Approve the expense.
4. Confirm audit log evidence.
5. Refresh/sync mobile.

Expected: authoritative statuses/balance changes return to mobile and match admin/source records.

## UAT-09 — Background GPS

With an active session and required permissions granted:

1. Put Field Sales in background.
2. Lock the screen for a practical field interval.
3. Walk/drive a safe short route.
4. Reopen the app.
5. Inspect server GPS history/live map.

Expected: tracking follows configured policy without duplicate/out-of-order current-location regression. Record any OEM battery-optimization warning/behavior.

## UAT-10 — End Day behavior

End the work session and leave the app backgrounded.

Expected: active-session state is cleared and tracking stops according to policy; no later GPS points are attributed as active-session tracking.

## UAT-11 — Device revocation

1. Revoke the UAT device from admin.
2. Attempt a protected mobile action using the existing session/token.

Expected: operation is denied with the documented device-revoked behavior. Reauthentication does not silently reactivate a revoked installation.

## UAT-12 — Notifications

1. Exercise notification preferences.
2. Generate an order/collection/expense review notification.
3. Generate suspicious-visit evidence only if the UAT scenario intentionally supports it.

Expected: in-app notification ownership/preferences are correct. Mark push delivery separately and only test it if a real provider is configured.

## UAT-13 — Reports

Use the same UAT data in admin reports.

Expected:

- filters show only the expected tenant/salesman/customer scope
- approved/verified values match source records
- currencies are never combined incorrectly
- CSV values match the filtered screen data

## UAT-14 — Operational health

During/after the UAT session check:

- `/up`
- `/ready`
- `field-sales:ops-check --backup-tooling`
- queue failed jobs
- oldest waiting/stale reservation thresholds
- server disk/log status

Expected: healthy throughout the normal UAT run.

## UAT-15 — Restore drill

Run only on non-production infrastructure:

1. Create a normal DB + media backup.
2. Verify the manifest/checksums.
3. Restore it into the approved non-production target.
4. Run migrations/readiness.
5. Verify the UAT business records and visit media.

Expected: restore succeeds and restored data matches the pre-backup state.

## Result record

For each scenario record PASS / FAIL / BLOCKED plus:

- UTC time
- screenshot/screen recording where useful
- server log/queue evidence for failures
- defect ID
- retest result

Never attach passwords, bearer tokens, keystore material or real customer production data.

Batch 19 is not complete until the required manual scenarios have actual execution evidence.
