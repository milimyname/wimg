#!/usr/bin/env python3
"""Try different HKKAZ account formats with Comdirect."""
import base64, getpass, requests

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

def send(url, msg, label=""):
    raw = msg.encode("iso-8859-1")
    r = requests.post(url, data=base64.b64encode(raw), headers={"Content-Type": "text/plain"})
    clean = r.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    decoded = base64.b64decode(clean).decode("iso-8859-1", errors="replace")
    print(f"  [{label}] {len(decoded)} bytes")
    for seg in decoded.split("'"):
        if seg.startswith("HIRMS") or seg.startswith("HIRMG"):
            print(f"    {seg[:150]}")
        if seg.startswith("HIKAZ"):
            print(f"    ✅ HIKAZ ({len(seg)} bytes): {seg[:100]}...")
    return decoded

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Init
send(URL, envelope("0", 1, f"HKIDN:2:2+280:{BLZ}+0+0+0'HKVVB:3:3+0+0+0+{PID}+1.0'"), "anon")
send(URL, envelope("0", 2, f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'HKVVB:3:3+0+0+0+{PID}+1.0'HKTAN:4:6+4+HKIDN'"), "auth")

# Try different HKKAZ formats
formats = [
    # Format 1: Ktonr::Laenderkennung:BLZ (v5 Kontoverbindung national)
    (f"HKKAZ:2:5+{kennung}::280:{BLZ}++2026-03-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'", "ktonr=kennung"),
    # Format 2: IBAN-based with SEPA Kontoverbindung (try HKCAZ v1 instead)
    (f"HKCAZ:2:1+++2026-03-01+2026-03-17++'HKTAN:3:6+4+HKCAZ'", "HKCAZ empty"),
    # Format 3: Just the kennung as account number
    (f"HKKAZ:2:5+{kennung}++2026-03-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'", "ktonr=kennung simple"),
    # Format 4: Kennung with full DEG
    (f"HKKAZ:2:5+{kennung}::{BLZ}++2026-03-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'", "ktonr:BLZ no country"),
]

for i, (inner, label) in enumerate(formats):
    print(f"\n--- Try {i+1}: {label} ---")
    send(URL, envelope("0", 3+i, inner), label)

# End
send(URL, envelope("0", 3+len(formats), "HKEND:2:1+0'"), "end")
print("\nDone.")
