#!/usr/bin/env python3
"""FinTS fetch with correct date format (YYYYMMDD) and Kontoverbindung."""
import base64, getpass, requests

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

def send(url, msg, label=""):
    raw = msg.encode("iso-8859-1")
    r = requests.post(url, data=base64.b64encode(raw), headers={"Content-Type": "text/plain"})
    clean = r.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    decoded = base64.b64decode(clean).decode("iso-8859-1", errors="replace")
    did = None
    for seg in decoded.split("'"):
        if seg.startswith("HNHBK"):
            did = seg.split("+")[3] if len(seg.split("+")) >= 4 else None
        if seg.startswith("HIRMS") or seg.startswith("HIRMG"):
            print(f"    {seg[:150]}")
        if seg.startswith("HIKAZ") and not seg.startswith("HIKAZS"):
            print(f"    ✅ HIKAZ ({len(seg)} bytes)")
            # Print first 300 chars of MT940
            print(f"    {seg[:300]}")
    return decoded, did

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Auth init
print("--- Auth init ---")
_, did = send(URL, envelope("0", 1,
    f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'"
    f"HKVVB:3:3+0+0+0+{PID}+1.0'"
    f"HKTAN:4:6+4+HKIDN'"), "auth")
print(f"  Dialog: {did}")

if did:
    # HKKAZ with FinTS date format YYYYMMDD (no dashes!)
    print("\n--- HKKAZ (dates as YYYYMMDD) ---")
    send(URL, envelope(did, 2,
        f"HKKAZ:2:5+{kennung}::280:{BLZ}++20260301+20260317++'"
        f"HKTAN:3:6+4+HKKAZ'"), "hkkaz")

    # Try HKCAZ (CAMT) too
    print("\n--- HKCAZ v1 (CAMT format) ---")
    send(URL, envelope(did, 3,
        f"HKCAZ:2:1+{kennung}::280:{BLZ}++20260301+20260317++'"
        f"HKTAN:3:6+4+HKCAZ'"), "hkcaz")

    # End
    send(URL, envelope(did, 4, f"HKEND:2:1+{did}'"), "end")

print("\nDone.")
