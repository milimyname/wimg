#!/usr/bin/env python3
"""Proper FinTS dialog with dialog ID tracking."""
import base64, getpass, requests

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

def send(url, msg, label=""):
    raw = msg.encode("iso-8859-1")
    r = requests.post(url, data=base64.b64encode(raw), headers={"Content-Type": "text/plain"})
    clean = r.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    decoded = base64.b64decode(clean).decode("iso-8859-1", errors="replace")
    print(f"\n  [{label}] {len(decoded)} bytes")

    dialog_id = None
    for seg in decoded.split("'"):
        if seg.startswith("HNHBK"):
            fields = seg.split("+")
            if len(fields) >= 4:
                dialog_id = fields[3]
                print(f"    Dialog-ID: {dialog_id}")
        if seg.startswith("HIRMS") or seg.startswith("HIRMG"):
            print(f"    {seg[:150]}")
        if seg.startswith("HIKAZ"):
            print(f"    ✅ HIKAZ ({len(seg)} bytes): {seg[:100]}...")
        if seg.startswith("HISPA"):
            print(f"    HISPA: {seg[:150]}")
        if seg.startswith("HIUPD"):
            print(f"    HIUPD: {seg[:150]}")

    return decoded, dialog_id

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Step 1: Auth init (gets dialog ID)
print("--- Step 1: Auth init (get dialog ID) ---")
resp, did = send(URL, envelope("0", 1,
    f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'"
    f"HKVVB:3:3+0+0+0+{PID}+1.0'"
    f"HKTAN:4:6+4+HKIDN'"), "auth")

if not did or did == "0":
    print("\n❌ No dialog ID received. Trying anon init first...")
    _, _ = send(URL, envelope("0", 1,
        f"HKIDN:2:2+280:{BLZ}+0+0+0'"
        f"HKVVB:3:3+0+0+0+{PID}+1.0'"), "anon")

    resp, did = send(URL, envelope("0", 1,
        f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'"
        f"HKVVB:3:3+0+0+0+{PID}+1.0'"
        f"HKTAN:4:6+4+HKIDN'"), "auth2")

print(f"\n  Using dialog ID: {did}")

if did and did != "0":
    # Step 2: HKSPA within the same dialog
    print("\n--- Step 2: HKSPA (get accounts) ---")
    resp2, _ = send(URL, envelope(did, 2,
        f"HKSPA:2:1'"
        f"HKTAN:3:6+4+HKSPA'"), "hkspa")

    # Step 3: HKKAZ within the same dialog
    print("\n--- Step 3: HKKAZ (fetch statements) ---")
    resp3, _ = send(URL, envelope(did, 3,
        f"HKKAZ:2:5+{kennung}::280:{BLZ}++2026-03-01+2026-03-17++'"
        f"HKTAN:3:6+4+HKKAZ'"), "hkkaz")

    # Step 4: End dialog
    print("\n--- Step 4: End dialog ---")
    send(URL, envelope(did, 4, f"HKEND:2:1+{did}'"), "end")
else:
    print("\n❌ Could not establish dialog")

print("\nDone.")
