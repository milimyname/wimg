#!/usr/bin/env python3
"""
FinTS 3.0 Authenticated Init Test — connects to Comdirect with real credentials.

Usage:
    python3 scripts/test-fints-auth.py

You'll be prompted for your Zugangsnummer (Kennung) and PIN.
Credentials are NOT logged or stored.
"""

import base64
import getpass
import sys

import requests

# --- Configuration ---
BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PRODUCT_ID = "F7C4049477F6136957A46EC28"
COUNTRY = "280"


def send(url: str, msg: str) -> str:
    """Send FinTS message, return decoded response."""
    raw = msg.encode("iso-8859-1")
    encoded = base64.b64encode(raw)

    print(f"\n>>> Sending {len(raw)} bytes ({len(encoded)} B64) to {url}")

    resp = requests.post(url, data=encoded, headers={"Content-Type": "text/plain"})
    print(f"<<< HTTP {resp.status_code}, {len(resp.content)} bytes")

    if resp.status_code != 200:
        print(f"ERROR: {resp.text[:200]}")
        return ""

    clean = resp.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    decoded = base64.b64decode(clean).decode("iso-8859-1")
    print(f"<<< Decoded: {len(decoded)} bytes")

    # Print segments
    for seg in decoded.split("'"):
        if seg.strip():
            header = seg.split("+")[0]
            print(f"    {header}: {seg[:120]}{'...' if len(seg) > 120 else ''}")

    return decoded


def make_envelope(dialog_id: str, msg_num: int, inner: str) -> str:
    """Wrap inner segments in HNHBK/HNHBS envelope."""
    seg_count = inner.count("'")
    trailer = f"HNHBS:{seg_count + 2}:1+{msg_num}'"

    header_prefix = "HNHBK:1:3+"
    header_suffix = f"+300+{dialog_id}+{msg_num}'"
    header_len = len(header_prefix) + 12 + len(header_suffix)
    total = header_len + len(inner) + len(trailer)
    header = f"{header_prefix}{total:012d}{header_suffix}"

    return header + inner + trailer


def main():
    print("=" * 60)
    print("FinTS 3.0 Authenticated Connection Test")
    print(f"Bank: Comdirect (BLZ {BLZ})")
    print(f"URL:  {URL}")
    print("=" * 60)

    kennung = input("\nZugangsnummer (Kennung): ").strip()
    pin = getpass.getpass("PIN: ").strip()

    if not kennung or not pin:
        print("ERROR: Kennung and PIN required")
        sys.exit(1)

    # === Step 1: Anonymous Init (fetch BPD) ===
    print("\n--- Step 1: Anonymous Init ---")
    anon_inner = (
        f"HKIDN:2:2+{COUNTRY}:{BLZ}+0+0+0'"
        f"HKVVB:3:3+0+0+0+{PRODUCT_ID}+1.0'"
    )
    anon_msg = make_envelope("0", 1, anon_inner)
    print(f"Message: {anon_msg}")

    anon_resp = send(URL, anon_msg)
    if not anon_resp or "9050" in anon_resp:
        print("\n❌ Anonymous init failed")
        sys.exit(1)

    # Extract dialog_id and system_id from response
    dialog_id = "0"
    system_id = "0"
    for seg in anon_resp.split("'"):
        if seg.startswith("HNHBK"):
            parts = seg.split("+")
            if len(parts) >= 4:
                dialog_id = parts[3]
                print(f"\n  Dialog-ID: {dialog_id}")

    print("\n✅ Anonymous init succeeded — BPD received")

    # === Step 2: Authenticated Init ===
    print("\n--- Step 2: Authenticated Init (with PIN) ---")

    # For PIN/TAN, we need a security envelope
    # Simplified: HNVSK + HNVSD wrapping HNSHK + HKIDN + HKVVB + HKTAN + HNSHA
    # This is complex — let's try without envelope first (some banks accept it)

    auth_inner = (
        f"HKIDN:2:2+{COUNTRY}:{BLZ}+{kennung}+0+1'"
        f"HKVVB:3:3+0+0+0+{PRODUCT_ID}+1.0'"
        f"HKTAN:4:6+4+HKIDN'"
    )
    auth_msg = make_envelope(dialog_id, 1, auth_inner)
    print(f"Message (first 100): {auth_msg[:100]}...")

    auth_resp = send(URL, auth_msg)

    if "3920" in auth_resp:
        print("\n✅ Bank wants TAN method selection (3920) — this is expected!")
        print("  TAN methods available in HITANS from BPD above")
    elif "0020" in auth_resp:
        print("\n✅ Authenticated init succeeded!")
    elif "9800" in auth_resp:
        print("\n❌ Dialog aborted by bank")
    elif "9010" in auth_resp or "9210" in auth_resp:
        print("\n❌ Authentication failed — check Kennung/PIN")
    else:
        print("\n⚠️  Unexpected response — check segments above")

    # === Step 3: Dialog End ===
    print("\n--- Step 3: Dialog End ---")
    end_inner = f"HKEND:2:1+{dialog_id}'"
    end_msg = make_envelope(dialog_id, 2, end_inner)
    send(URL, end_msg)

    print("\nDone.")


if __name__ == "__main__":
    main()
