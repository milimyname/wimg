#!/usr/bin/env python3
"""Try HKKAZ with full HKTAN v6 fields."""
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
            print(f"    {seg[:300]}")
        if seg.startswith("HICAZ") and not seg.startswith("HICAZS"):
            print(f"    ✅ HICAZ ({len(seg)} bytes)")
            print(f"    {seg[:300]}")
        if seg.startswith("HITAN"):
            print(f"    HITAN: {seg[:150]}")
    return decoded, did

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Auth
print("--- Auth ---")
_, did = send(URL, envelope("0", 1,
    f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'"
    f"HKVVB:3:3+0+0+0+{PID}+1.0'"
    f"HKTAN:4:6+4+HKIDN'"), "auth")
print(f"  DID: {did}")

if did:
    # Try 1: HKKAZ v5 + HKTAN v6 with more fields
    print("\n--- Try 1: HKKAZ v5, HKTAN with empty optionals ---")
    send(URL, envelope(did, 2,
        f"HKKAZ:2:5+{kennung}::280:{BLZ}++20260301+20260317++'"
        f"HKTAN:3:6+4+HKKAZ++++N+N'"), "hkkaz-full-tan")

    # Try 2: Without HKTAN entirely (maybe not needed for "nochallenge" session)
    print("\n--- Try 2: HKKAZ v5 without HKTAN ---")
    send(URL, envelope(did, 3,
        f"HKKAZ:2:5+{kennung}::280:{BLZ}++20260301+20260317++'"), "hkkaz-no-tan")

    # Try 3: HKKAZ v6 (Account3 format)
    print("\n--- Try 3: HKKAZ v6 ---")
    send(URL, envelope(did, 4,
        f"HKKAZ:2:6+{kennung}::280:{BLZ}++20260301+20260317++'"
        f"HKTAN:3:6+4+HKKAZ'"), "hkkaz-v6")

    # End
    send(URL, envelope(did, 5, f"HKEND:2:1+{did}'"), "end")

print("\nDone.")
