#!/usr/bin/env python3
"""
FinTS 3.0 Anonymous Init Test — sends a BPD request to Comdirect.

Usage:
    python3 scripts/test-fints.py

This builds the same anonymous init message as wimg's Zig code
and sends it to Comdirect's FinTS endpoint. Use this to debug
protocol issues by comparing with working clients like python-fints.
"""

import base64
import sys

import requests

# --- Configuration ---
BLZ = "20041133"
URL = "https://fints.comdirect.de/fints"
PRODUCT_ID = "F7C4049477F6136957A46EC28"  # Registered with DK
COUNTRY = "280"  # Germany


def build_anonymous_init() -> bytes:
    """Build a FinTS 3.0 anonymous init message (HNHBK + HKIDN + HKVVB + HNHBS)."""

    # Inner segments (HKIDN + HKVVB)
    # HKIDN:2:2 — segment num 2, version 2
    # DEG Kreditinstitutskennung = 280:BLZ (colon is DEG separator, not escaped)
    hkidn = f"HKIDN:2:2+{COUNTRY}:{BLZ}+0+0+0'"

    # HKVVB:3:3 — segment num 3, version 3
    hkvvb = f"HKVVB:3:3+0+0+0+{PRODUCT_ID}+1.0'"

    # HNHBS:4:1 — trailer
    hnhbs = "HNHBS:4:1+1'"

    inner = hkidn + hkvvb

    # HNHBK:1:3 — header with 12-digit message size
    # Size includes the header itself
    # Header template: HNHBK:1:3+XXXXXXXXXXXX+300+0+1'
    header_prefix = "HNHBK:1:3+"
    header_suffix = "+300+0+1'"
    # Calculate total: header + inner + trailer
    # Header has 12-digit size field as placeholder
    header_len = len(header_prefix) + 12 + len(header_suffix)
    total = header_len + len(inner) + len(hnhbs)
    size_str = f"{total:012d}"
    header = f"{header_prefix}{size_str}{header_suffix}"

    msg = header + inner + hnhbs

    print(f"=== Raw FinTS Message ({len(msg)} bytes) ===")
    print(msg)
    print()

    # Verify size matches
    assert len(msg) == total, f"Size mismatch: declared {total}, actual {len(msg)}"

    return msg.encode("iso-8859-1")


def send_fints(url: str, message: bytes) -> bytes:
    """Send a FinTS message (Base64-encoded) and return the decoded response."""
    encoded = base64.b64encode(message)

    print(f"=== Sending to {url} ===")
    print(f"Base64 body ({len(encoded)} bytes): {encoded[:80]}...")
    print()

    resp = requests.post(
        url,
        data=encoded,
        headers={"Content-Type": "text/plain"},
    )

    print(f"=== Response: HTTP {resp.status_code}, {len(resp.content)} bytes ===")

    if resp.status_code != 200:
        print(f"ERROR: HTTP {resp.status_code}")
        print(resp.text[:500])
        return b""

    # Decode Base64 response (may contain newlines)
    raw = resp.content.decode("iso-8859-1")
    clean = raw.replace("\n", "").replace("\r", "").replace(" ", "")
    decoded = base64.b64decode(clean)

    print(f"Decoded ({len(decoded)} bytes):")
    print(decoded.decode("iso-8859-1", errors="replace"))
    print()

    return decoded


def parse_response(data: bytes):
    """Parse FinTS response segments and print them."""
    text = data.decode("iso-8859-1", errors="replace")
    segments = text.split("'")

    print("=== Parsed Segments ===")
    for seg in segments:
        if not seg.strip():
            continue
        # Extract segment header
        parts = seg.split("+", 1)
        header = parts[0]
        print(f"  {header}")
        if len(parts) > 1:
            des = parts[1].split("+")
            for i, de in enumerate(des):
                print(f"    DE{i+1}: {de}")
    print()


def main():
    print("=" * 60)
    print("FinTS 3.0 Anonymous Init Test")
    print(f"Bank: Comdirect (BLZ {BLZ})")
    print(f"URL:  {URL}")
    print(f"Product: {PRODUCT_ID}")
    print("=" * 60)
    print()

    msg = build_anonymous_init()
    resp = send_fints(URL, msg)

    if resp:
        parse_response(resp)

        # Check for errors
        text = resp.decode("iso-8859-1")
        if "9050" in text:
            print("❌ Bank says: Die Nachricht enthaelt Fehler")
        if "9800" in text:
            print("❌ Bank says: Dialog abgebrochen")
        if "9110" in text:
            print("❌ Error 9110: Unzulässiger Wert (invalid value in a field)")
        if "0010" in text or "0020" in text:
            print("✅ Success! Bank accepted the message")
        if "HIBPA" in text:
            print("✅ Received BPD (Bank Parameter Data)")

    print()
    print("--- Compare with python-fints ---")
    print("pip install python-fints")
    print("Then use: from fints.client import FinTS3PinTanClient")
    print(f'client = FinTS3PinTanClient("{BLZ}", "USER", "PIN", "{URL}")')
    print("This will show what a working implementation sends.")


if __name__ == "__main__":
    main()
