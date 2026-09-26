# FieldPulse Android — Batch 19 UAT Evidence Record

Copy this file for each release-candidate execution. Do not overwrite the template.

Suggested result filename:

```text
UAT_RESULTS_<YYYY-MM-DD>_<RC-VERSION>.md
```

Do not record passwords, bearer tokens, signing secrets, private keys, or real customer production data.

## Release-candidate identity

| Field | Value |
|---|---|
| UAT execution date (UTC) | |
| Tester | |
| Web commit SHA | |
| Mobile commit SHA | |
| App version / build number | |
| APK SHA-256 | |
| API base URL / environment name | |
| UAT tenant | |
| Android device manufacturer/model | |
| Android version | |
| OEM battery-optimization state | |
| Network types exercised | |
| UAT start time (UTC) | |
| UAT end time (UTC) | |

## Preflight

| Check | Result | Evidence / Notes |
|---|---|---|
| Approved app icon/splash present | NOT EXECUTED | |
| Signed RC APK checksum recorded | NOT EXECUTED | |
| HTTPS API endpoint correct | NOT EXECUTED | |
| `/up` healthy | NOT EXECUTED | |
| `/ready` healthy | NOT EXECUTED | |
| Queue workers healthy | NOT EXECUTED | |
| Scheduler healthy | NOT EXECUTED | |
| Operations monitor healthy | NOT EXECUTED | |
| UAT tenant/test data prepared | NOT EXECUTED | |

Use only: `PASS`, `FAIL`, `BLOCKED`, or `NOT EXECUTED`.

## Scenario results

| ID | Scenario | Result | UTC time | Evidence | Defect ID | Retest |
|---|---|---|---|---|---|---|
| UAT-01 | Clean install and launch | NOT EXECUTED | | | | |
| UAT-02 | Login, tenant selection, leadership and device binding | NOT EXECUTED | | | | |
| UAT-03 | Privacy and permissions | NOT EXECUTED | | | | |
| UAT-04 | Start Day and online GPS | NOT EXECUTED | | | | |
| UAT-05 | Full offline field workflow | NOT EXECUTED | | | | |
| UAT-06 | Process restart while offline | NOT EXECUTED | | | | |
| UAT-07 | Reconnect and synchronize | NOT EXECUTED | | | | |
| UAT-08 | Admin review round-trip | NOT EXECUTED | | | | |
| UAT-09 | Background GPS | NOT EXECUTED | | | | |
| UAT-10 | End Day, accidental close recovery and final stop | NOT EXECUTED | | | | |
| UAT-11 | Device revocation | NOT EXECUTED | | | | |
| UAT-12 | Notifications/preferences | NOT EXECUTED | | | | |
| UAT-13 | Reports/CSV | NOT EXECUTED | | | | |
| UAT-14 | Operational health | NOT EXECUTED | | | | |
| UAT-15 | Non-production restore drill | NOT EXECUTED | | | | |

Detailed execution steps and expected behavior remain in `UAT.md`.

## Offline/reconnect evidence

Record the local/server identifiers used to prove retry safety without exposing credentials.

| Entity | Offline/client UUID | Server UUID/ID after sync | Duplicate count expected | Duplicate count observed |
|---|---|---|---:|---:|
| Attendance session | | | 1 | |
| Visit | | | 1 | |
| Order | | | 1 | |
| Collection | | | 1 | |
| Expense | | | 1 | |

Record:
- tenant code used / ambiguity behavior:
- supervisor same-installation login result:
- remembered tenant prefill result:
- airplane-mode start/end time:
- application force-stop/restart time:
- reconnect time:
- first successful sync time:
- second/retry sync result:
- blocked/retryable failures observed:

## GPS evidence

Record:
- Start Day time:
- foreground GPS points observed:
- background/screen-locked interval:
- admin live-map last-location time:
- oldest/newest GPS timestamps:
- out-of-order or duplicate points observed:
- accidental End Day time:
- Reopen Day time / same-session verification:
- final End Day time:
- any GPS point received after final End Day:
- OEM battery-optimization behavior:

## Admin round-trip evidence

Record the authoritative final state after server review:

| Entity | Mobile-created value/status | Admin action | Final server status/value | Mobile refresh result |
|---|---|---|---|---|
| Order | | | | |
| Collection | | | | |
| Expense | | | | |

## Reports reconciliation

Record the filtered UAT report parameters and source totals:

| Report | Filter | UI result | CSV result | Source record result | Match |
|---|---|---|---|---|---|
| Sales | | | | | |
| Visits | | | | | |
| GPS/performance | | | | | |

For monetary values, record each currency independently.

## Operational evidence

| Check | Before UAT | During UAT | After UAT | Notes |
|---|---|---|---|---|
| `/up` | | | | |
| `/ready` | | | | |
| `field-sales:ops-check --backup-tooling` | | | | |
| Failed jobs | | | | |
| Waiting jobs | | | | |
| Stale reserved jobs | | | | |
| Disk space | | | | |
| Recent application errors | | | | |

## Restore drill evidence

Run only on an approved non-production target.

Record:
- backup directory/reference:
- manifest SHA/check result:
- database archive checksum:
- media archive checksum:
- restore target:
- restore start/end time:
- post-restore migration result:
- post-restore `/ready` result:
- restored order/collection/expense IDs checked:
- restored visit-media item checked:
- discrepancies:

## Defects

| Defect ID | UAT scenario | Severity | Description | Fix SHA | Retest result | Release blocker |
|---|---|---|---|---|---|---|
| | | | | | | |

## Final acceptance

- [ ] UAT-01 through UAT-14 are PASS, or any exception has documented non-release-blocking acceptance.
- [ ] UAT-15 restore drill is PASS.
- [ ] No unresolved release-blocking defect remains.
- [ ] Approved production icon/splash branding is present.
- [ ] Real release APK is signed with the intended external key and checksum recorded.
- [ ] Production-like HTTPS environment and operational checks are healthy.
- [ ] Final web/mobile SHAs are recorded.
- [ ] Release candidate is approved for Batch 20 promotion.

Final decision: **NOT APPROVED / APPROVED FOR BATCH 20**

Approver:
Approval time (UTC):
Notes:
