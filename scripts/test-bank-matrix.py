#!/usr/bin/env python3
"""
Top-bank FinTS anonymous-init smoke matrix.

What it tests (no credentials required):
- Endpoint reachability + FinTS envelope acceptance
- BPD presence (HIBPA)
- HIKAZS / HICAZS support advertisement
- HITANS TAN method IDs

Usage:
    python3 scripts/test-bank-matrix.py
    python3 scripts/test-bank-matrix.py --timeout 20
"""

from __future__ import annotations

import argparse
import base64
import dataclasses
import json
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import requests

PRODUCT_ID = "F7C4049477F6136957A46EC28"
COUNTRY = "280"


@dataclasses.dataclass
class BankInfo:
    blz: str
    bic: str
    name: str
    url: str


@dataclasses.dataclass
class ProbeResult:
    label: str
    blz: str
    name: str
    url: str
    endpoint_ok: bool
    bpd_ok: bool
    structural_ok: bool
    hikaz_versions: List[str]
    has_hicazs: bool
    tan_methods: List[str]
    response_codes: List[str]
    http_status: Optional[int]
    error: str
    variant: str


def build_anonymous_init(blz: str) -> bytes:
    hkidn = f"HKIDN:2:2+{COUNTRY}:{blz}+0+0+0'"
    hkvvb = f"HKVVB:3:3+0+0+0+{PRODUCT_ID}+1.0'"
    inner = hkidn + hkvvb
    hnhbs = "HNHBS:4:1+1'"

    header_prefix = "HNHBK:1:3+"
    header_suffix = "+300+0+1'"
    header_len = len(header_prefix) + 12 + len(header_suffix)
    total = header_len + len(inner) + len(hnhbs)
    header = f"{header_prefix}{total:012d}{header_suffix}"
    msg = header + inner + hnhbs
    return msg.encode("iso-8859-1")


def build_anonymous_init_with_hksyn(blz: str) -> bytes:
    hkidn = f"HKIDN:2:2+{COUNTRY}:{blz}+0+0+0'"
    hkvvb = f"HKVVB:3:3+0+0+0+{PRODUCT_ID}+5.0.0'"
    hksyn = "HKSYN:4:3+0'"
    inner = hkidn + hkvvb + hksyn
    hnhbs = "HNHBS:5:1+1'"

    header_prefix = "HNHBK:1:3+"
    header_suffix = "+300+0+1'"
    header_len = len(header_prefix) + 12 + len(header_suffix)
    total = header_len + len(inner) + len(hnhbs)
    header = f"{header_prefix}{total:012d}{header_suffix}"
    msg = header + inner + hnhbs
    return msg.encode("iso-8859-1")


def decode_fints_response(raw_bytes: bytes) -> str:
    raw = raw_bytes.decode("iso-8859-1", errors="replace")
    clean = raw.replace("\n", "").replace("\r", "").replace(" ", "")
    decoded = base64.b64decode(clean)
    return decoded.decode("iso-8859-1", errors="replace")


def parse_segment_version(segment_header: str) -> Optional[str]:
    # Segment header format e.g. HIKAZS:4:7
    parts = segment_header.split(":")
    if len(parts) < 3:
        return None
    version = parts[2]
    return version if version.isdigit() else None


def analyze_response(decoded_text: str) -> Tuple[bool, bool, List[str], bool, List[str], List[str]]:
    segments = [s for s in decoded_text.split("'") if s]

    bpd_ok = any(seg.startswith("HIBPA") for seg in segments)
    code_list = re.findall(r"([0-9]{4}):", decoded_text)
    codes = sorted(set(code_list))
    structural_ok = "9110" not in codes

    hikaz_versions: List[str] = []
    has_hicazs = False
    tan_methods: set[str] = set()

    for seg in segments:
        if seg.startswith("HIKAZS:"):
            header = seg.split("+", 1)[0]
            ver = parse_segment_version(header)
            if ver is not None:
                hikaz_versions.append(ver)
        elif seg.startswith("HICAZS:"):
            has_hicazs = True
        elif seg.startswith("HITANS:"):
            body = seg.split("+")[1:]  # skip HITANS header
            for field in body:
                m = re.match(r"^([0-9]{3}):[0-9A-Z]:", field)
                if m:
                    tan_methods.add(m.group(1))

    hikaz_versions = sorted(set(hikaz_versions), key=int)
    tan_methods_sorted = sorted(tan_methods)
    return bpd_ok, structural_ok, hikaz_versions, has_hicazs, tan_methods_sorted, codes


def send_anonymous_probe(bank: BankInfo, timeout_s: float, variant: str = "anon") -> ProbeResult:
    try:
        if variant == "anon_hksyn":
            msg = build_anonymous_init_with_hksyn(bank.blz)
        else:
            msg = build_anonymous_init(bank.blz)
        body = base64.b64encode(msg)
        resp = requests.post(
            bank.url,
            data=body,
            headers={"Content-Type": "text/plain"},
            timeout=timeout_s,
        )

        if resp.status_code != 200:
            return ProbeResult(
                label=bank.name,
                blz=bank.blz,
                name=bank.name,
                url=bank.url,
                endpoint_ok=False,
                bpd_ok=False,
                structural_ok=False,
                hikaz_versions=[],
                has_hicazs=False,
                tan_methods=[],
                response_codes=[],
                http_status=resp.status_code,
                error=f"HTTP {resp.status_code}",
                variant=variant,
            )

        decoded = decode_fints_response(resp.content)
        bpd_ok, structural_ok, hikaz_versions, has_hicazs, tan_methods, response_codes = analyze_response(decoded)
        return ProbeResult(
            label=bank.name,
            blz=bank.blz,
            name=bank.name,
            url=bank.url,
            endpoint_ok=True,
            bpd_ok=bpd_ok,
            structural_ok=structural_ok,
            hikaz_versions=hikaz_versions,
            has_hicazs=has_hicazs,
            tan_methods=tan_methods,
            response_codes=response_codes,
            http_status=resp.status_code,
            error="",
            variant=variant,
        )
    except Exception as exc:  # noqa: BLE001
        return ProbeResult(
            label=bank.name,
            blz=bank.blz,
            name=bank.name,
            url=bank.url,
            endpoint_ok=False,
            bpd_ok=False,
            structural_ok=False,
            hikaz_versions=[],
            has_hicazs=False,
            tan_methods=[],
            response_codes=[],
            http_status=None,
            error=str(exc),
            variant=variant,
        )


def choose_better_result(primary: ProbeResult, secondary: ProbeResult) -> ProbeResult:
    # Prefer any successful endpoint response over transport error.
    if not primary.endpoint_ok and secondary.endpoint_ok:
        return secondary
    if primary.endpoint_ok and not secondary.endpoint_ok:
        return primary

    # Prefer richer protocol result: BPD + structural success + more discovered fields.
    primary_score = (
        int(primary.bpd_ok) * 4
        + int(primary.structural_ok) * 2
        + int(bool(primary.hikaz_versions))
        + int(primary.has_hicazs)
    )
    secondary_score = (
        int(secondary.bpd_ok) * 4
        + int(secondary.structural_ok) * 2
        + int(bool(secondary.hikaz_versions))
        + int(secondary.has_hicazs)
    )
    return secondary if secondary_score > primary_score else primary


def parse_banks_zig(path: Path) -> Dict[str, BankInfo]:
    text = path.read_text(encoding="utf-8")
    # makeBank("BLZ", "BIC", "Name", "URL")
    pattern = re.compile(
        r'makeBank\("(?P<blz>\d{8})",\s*"(?P<bic>[^"]*)",\s*"(?P<name>[^"]*)",\s*"(?P<url>[^"]*)"\)'
    )
    out: Dict[str, BankInfo] = {}
    for m in pattern.finditer(text):
        blz = m.group("blz")
        out[blz] = BankInfo(
            blz=blz,
            bic=m.group("bic"),
            name=m.group("name"),
            url=m.group("url"),
        )
    return out


def choose_atruvia_representative(banks_by_blz: Dict[str, BankInfo]) -> Optional[BankInfo]:
    candidates = [
        b
        for b in banks_by_blz.values()
        if "fints1.atruvia.de/cgi-bin/hbciservlet" in b.url
        and ("Volksbank" in b.name or "Raiffeisenbank" in b.name or "VR Bank" in b.name)
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda b: b.blz)
    return candidates[0]


def build_target_list(banks_by_blz: Dict[str, BankInfo]) -> List[Tuple[str, BankInfo]]:
    targets: List[Tuple[str, str]] = [
        ("Comdirect", "20041177"),
        ("Berliner Sparkasse", "10050000"),
        ("Deutsche Bank", "10070000"),
        ("Commerzbank", "10040000"),
        ("Postbank", "10010010"),
        ("ING", "50010517"),
        ("DKB", "12030000"),
    ]

    out: List[Tuple[str, BankInfo]] = []
    for label, blz in targets:
        bank = banks_by_blz.get(blz)
        if bank is not None:
            out.append((label, bank))

    atruvia = choose_atruvia_representative(banks_by_blz)
    if atruvia is not None:
        out.append(("Atruvia representative", atruvia))
    return out


def yes_no(value: bool) -> str:
    return "YES" if value else "NO"


def print_matrix(results: List[ProbeResult]) -> None:
    cols = [
        ("Bank", 24),
        ("BLZ", 8),
        ("Endpoint", 8),
        ("BPD", 4),
        ("Struct", 6),
        ("HIKAZS", 8),
        ("HICAZS", 6),
        ("TAN methods", 18),
        ("Codes", 20),
        ("Variant", 10),
    ]
    header = "  ".join(name.ljust(width) for name, width in cols)
    sep = "  ".join("-" * width for _, width in cols)
    print(header)
    print(sep)
    for r in results:
        hikaz = ",".join(r.hikaz_versions) if r.hikaz_versions else "-"
        tan = ",".join(r.tan_methods) if r.tan_methods else "-"
        codes = ",".join(r.response_codes) if r.response_codes else "-"
        row = [
            r.label[:24].ljust(24),
            r.blz.ljust(8),
            yes_no(r.endpoint_ok).ljust(8),
            yes_no(r.bpd_ok).ljust(4),
            yes_no(r.structural_ok).ljust(6),
            hikaz[:8].ljust(8),
            yes_no(r.has_hicazs).ljust(6),
            tan[:18].ljust(18),
            codes[:20].ljust(20),
            r.variant[:10].ljust(10),
        ]
        print("  ".join(row))
        if r.error:
            print(f"    error: {r.error}")
        print(f"    url: {r.url}")


def main() -> None:
    parser = argparse.ArgumentParser(description="FinTS top-bank anonymous-init matrix")
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout in seconds per bank")
    parser.add_argument(
        "--try-hksyn-variant",
        action="store_true",
        help="if anon probe is weak, also try anon+HKSYN variant and keep the better result",
    )
    parser.add_argument(
        "--json-out",
        default="scripts/bank-matrix-last.json",
        help="path to write JSON report",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    banks_path = repo_root / "libwimg" / "src" / "banks.zig"
    banks_by_blz = parse_banks_zig(banks_path)
    targets = build_target_list(banks_by_blz)

    print(f"Running anonymous FinTS probes for {len(targets)} banks (timeout={args.timeout:.1f}s)")
    print()

    results: List[ProbeResult] = []
    for label, bank in targets:
        print(f"- probing {label} ({bank.blz}) ...")
        primary = send_anonymous_probe(
            BankInfo(blz=bank.blz, bic=bank.bic, name=label, url=bank.url),
            timeout_s=args.timeout,
            variant="anon",
        )
        chosen = primary
        if args.try_hksyn_variant and (not primary.bpd_ok or not primary.structural_ok):
            print("  -> trying anon_hksyn variant ...")
            secondary = send_anonymous_probe(
                BankInfo(blz=bank.blz, bic=bank.bic, name=label, url=bank.url),
                timeout_s=args.timeout,
                variant="anon_hksyn",
            )
            chosen = choose_better_result(primary, secondary)
        results.append(chosen)

    print()
    print_matrix(results)

    endpoint_ok = sum(1 for r in results if r.endpoint_ok)
    bpd_ok = sum(1 for r in results if r.bpd_ok)
    structural_ok = sum(1 for r in results if r.structural_ok)
    print()
    print(
        f"Summary: endpoint_ok={endpoint_ok}/{len(results)}, "
        f"bpd_ok={bpd_ok}/{len(results)}, structural_ok={structural_ok}/{len(results)}"
    )

    json_path = Path(args.json_out)
    payload = {
        "summary": {
            "count": len(results),
            "endpoint_ok": endpoint_ok,
            "bpd_ok": bpd_ok,
            "structural_ok": structural_ok,
            "timeout_seconds": args.timeout,
        },
        "results": [dataclasses.asdict(r) for r in results],
    }
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"JSON report written: {json_path}")


if __name__ == "__main__":
    main()
