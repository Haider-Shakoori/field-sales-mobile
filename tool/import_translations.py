#!/usr/bin/env python3
"""Import FieldPulse translation CSV into Flutter language catalogs.

Usage:
  python3 tool/import_translations.py translations/fieldpulse_mobile_translation_template.csv
  python3 tool/import_translations.py translations/fieldpulse_mobile_translation_template.csv --validate-only
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

REQUIRED_COLUMNS = {
    "key",
    "english_en",
    "dari_fa_AF",
    "pashto_ps_AF",
    "placeholders",
}


def placeholders(value: str) -> set[str]:
    return {part.strip() for part in value.split(";") if part.strip()}


def in_text(value: str) -> set[str]:
    return set(re.findall(r"\{([^{}]+)\}", value or ""))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    with args.csv_file.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"Missing CSV columns: {', '.join(sorted(missing))}")
        rows = list(reader)

    seen: set[str] = set()
    errors: list[str] = []
    catalogs = {"en": {}, "fa": {}, "ps": {}}

    for row_number, row in enumerate(rows, start=2):
        key = (row.get("key") or "").strip()
        if not key:
            errors.append(f"row {row_number}: key is empty")
            continue
        if key in seen:
            errors.append(f"row {row_number}: duplicate key {key}")
            continue
        seen.add(key)

        expected = placeholders(row.get("placeholders") or "")
        english = row.get("english_en") or ""
        dari = row.get("dari_fa_AF") or ""
        pashto = row.get("pashto_ps_AF") or ""

        if expected != in_text(english):
            errors.append(
                f"row {row_number} ({key}): English placeholders do not match "
                f"the placeholders column"
            )

        for locale, value in (("fa", dari), ("ps", pashto)):
            if value.strip() and expected != in_text(value):
                errors.append(
                    f"row {row_number} ({key}): {locale} placeholders must be "
                    f"exactly {sorted(expected)}"
                )

        catalogs["en"][key] = english
        catalogs["fa"][key] = dari
        catalogs["ps"][key] = pashto

    if errors:
        print("\n".join(errors))
        return 1

    if args.validate_only:
        print(f"Validated {len(rows)} translation rows.")
        return 0

    output = Path("assets/lang")
    output.mkdir(parents=True, exist_ok=True)
    for locale, catalog in catalogs.items():
        (output / f"{locale}.json").write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print(
        f"Imported {len(rows)} rows into "
        "assets/lang/en.json, fa.json and ps.json."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
