#!/usr/bin/env python3
"""
Bank catalog drift checker.

Compares the official FinTS institute CSV (from Deutsche Kreditwirtschaft)
against banks.zig to detect:
- Missing banks (have FinTS URL in CSV but not in our catalog)
- URL changes (same BLZ, different URL)
- Removed banks (in our catalog but no longer in CSV with a FinTS URL)

Usage:
    python3 scripts/check-bank-drift.py path/to/fints_institute.csv
    python3 scripts/check-bank-drift.py path/to/fints_institute.csv --json-out drift-report.json
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional


class CsvBank(NamedTuple):
    blz: str
    bic: str
    name: str
    url: str


class ZigBank(NamedTuple):
    blz: str
    bic: str
    name: str
    url: str


def parse_official_csv(path: Path) -> Dict[str, CsvBank]:
    """Parse the official FinTS institute CSV.

    The CSV has semicolon-separated fields. Expected columns (by header name):
    - Bankleitzahl (BLZ)
    - BIC
    - Bezeichnung (bank name)
    - URL (FinTS endpoint)

    The file may use different column names across versions, so we try
    multiple known header variants.
    """
    banks: Dict[str, CsvBank] = {}

    # Try multiple encodings (official file is typically latin-1 or cp1252)
    content = None
    for enc in ("utf-8-sig", "cp1252", "latin-1", "utf-8"):
        try:
            content = path.read_text(encoding=enc)
            break
        except (UnicodeDecodeError, UnicodeError):
            continue

    if content is None:
        raise ValueError(f"Cannot decode {path} with any supported encoding")

    # Detect delimiter (semicolon or comma)
    first_line = content.split("\n", 1)[0]
    delimiter = ";" if ";" in first_line else ","

    reader = csv.DictReader(content.splitlines(), delimiter=delimiter)
    if reader.fieldnames is None:
        raise ValueError(f"No header found in {path}")

    # Normalize field names for matching
    field_map: Dict[str, str] = {}
    for f in reader.fieldnames:
        fl = f.strip().lower()
        if "bankleitzahl" in fl or fl == "blz":
            field_map["blz"] = f
        elif fl == "bic" or "bic" in fl:
            field_map["bic"] = f
        elif "bezeichnung" in fl or "name" in fl or "institut" in fl:
            field_map["name"] = f
        elif "url" in fl or "pin/tan" in fl or "fints" in fl.replace("-", "").replace(" ", ""):
            field_map["url"] = f

    if "blz" not in field_map:
        raise ValueError(
            f"Cannot find BLZ column. Available columns: {reader.fieldnames}"
        )

    for row in reader:
        blz = row.get(field_map.get("blz", ""), "").strip()
        if not blz or not blz.isdigit():
            continue

        # Pad BLZ to 8 digits
        blz = blz.zfill(8)

        url = row.get(field_map.get("url", ""), "").strip()
        bic = row.get(field_map.get("bic", ""), "").strip()
        name = row.get(field_map.get("name", ""), "").strip()

        # Only include banks with a FinTS URL
        if not url or not url.startswith("http"):
            continue

        # Normalize URL: strip trailing slashes for consistent comparison
        url = url.rstrip("/")

        # Keep first occurrence per BLZ (some CSVs have duplicates)
        if blz not in banks:
            banks[blz] = CsvBank(blz=blz, bic=bic, name=name, url=url)

    return banks


def parse_banks_zig(path: Path) -> Dict[str, ZigBank]:
    """Parse banks.zig to extract all makeBank entries."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        r'makeBank\("(?P<blz>\d{8})",\s*"(?P<bic>[^"]*)",\s*"(?P<name>[^"]*)",\s*"(?P<url>[^"]*)"\)'
    )
    banks: Dict[str, ZigBank] = {}
    for m in pattern.finditer(text):
        blz = m.group("blz")
        banks[blz] = ZigBank(
            blz=blz,
            bic=m.group("bic"),
            name=m.group("name"),
            url=m.group("url").rstrip("/"),
        )
    return banks


def normalize_url(url: str) -> str:
    """Normalize URL for comparison (lowercase host, strip trailing slash)."""
    return url.rstrip("/").lower()


def check_drift(
    csv_banks: Dict[str, CsvBank], zig_banks: Dict[str, ZigBank]
) -> tuple[list, list, list]:
    """Compare CSV against banks.zig. Returns (missing, url_changes, removed)."""

    missing: List[Dict] = []
    url_changes: List[Dict] = []
    removed: List[Dict] = []

    # Banks in CSV but not in banks.zig
    for blz, cb in sorted(csv_banks.items()):
        if blz not in zig_banks:
            missing.append({
                "blz": blz,
                "bic": cb.bic,
                "name": cb.name,
                "url": cb.url,
            })
        else:
            zb = zig_banks[blz]
            if normalize_url(cb.url) != normalize_url(zb.url):
                url_changes.append({
                    "blz": blz,
                    "name": cb.name,
                    "old_url": zb.url,
                    "new_url": cb.url,
                })

    # Banks in banks.zig but not in CSV (may have been removed from FinTS)
    for blz, zb in sorted(zig_banks.items()):
        if blz not in csv_banks:
            removed.append({
                "blz": blz,
                "name": zb.name,
                "url": zb.url,
            })

    return missing, url_changes, removed


def print_report(
    missing: list, url_changes: list, removed: list,
    csv_count: int, zig_count: int,
) -> None:
    print(f"Official CSV: {csv_count} banks with FinTS URLs")
    print(f"banks.zig:    {zig_count} banks")
    print()

    if not missing and not url_changes and not removed:
        print("No drift detected. banks.zig is up to date.")
        return

    if missing:
        print(f"MISSING ({len(missing)} banks in CSV but not in banks.zig):")
        print("-" * 80)
        for b in missing[:30]:  # Show first 30
            print(f"  {b['blz']}  {b['name'][:40]:<40}  {b['url']}")
        if len(missing) > 30:
            print(f"  ... and {len(missing) - 30} more")
        print()

    if url_changes:
        print(f"URL CHANGES ({len(url_changes)} banks with different URLs):")
        print("-" * 80)
        for b in url_changes:
            print(f"  {b['blz']}  {b['name'][:40]}")
            print(f"    old: {b['old_url']}")
            print(f"    new: {b['new_url']}")
        print()

    if removed:
        print(f"REMOVED ({len(removed)} banks in banks.zig but not in CSV):")
        print("-" * 80)
        for b in removed[:30]:
            print(f"  {b['blz']}  {b['name'][:40]:<40}  {b['url']}")
        if len(removed) > 30:
            print(f"  ... and {len(removed) - 30} more")
        print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check bank catalog drift between official CSV and banks.zig"
    )
    parser.add_argument(
        "csv_path",
        type=Path,
        help="Path to official FinTS institute CSV file",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="Write JSON drift report to this path",
    )
    args = parser.parse_args()

    if not args.csv_path.exists():
        print(f"Error: CSV file not found: {args.csv_path}")
        return

    repo_root = Path(__file__).resolve().parents[1]
    banks_zig_path = repo_root / "libwimg" / "src" / "banks.zig"

    if not banks_zig_path.exists():
        print(f"Error: banks.zig not found at {banks_zig_path}")
        return

    csv_banks = parse_official_csv(args.csv_path)
    zig_banks = parse_banks_zig(banks_zig_path)

    print(f"Parsed {len(csv_banks)} banks from CSV, {len(zig_banks)} from banks.zig")
    print()

    missing, url_changes, removed = check_drift(csv_banks, zig_banks)
    print_report(missing, url_changes, removed, len(csv_banks), len(zig_banks))

    if args.json_out:
        report = {
            "summary": {
                "csv_count": len(csv_banks),
                "zig_count": len(zig_banks),
                "missing_count": len(missing),
                "url_change_count": len(url_changes),
                "removed_count": len(removed),
            },
            "missing": missing,
            "url_changes": url_changes,
            "removed": removed,
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"JSON report written: {args.json_out}")


if __name__ == "__main__":
    main()
