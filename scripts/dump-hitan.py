#!/usr/bin/env python3
"""Dump the HITAN segment from Comdirect to see photoTAN field positions."""
import base64, getpass, requests

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

def send(url, msg):
    raw = msg.encode("iso-8859-1")
    r = requests.post(url, data=base64.b64encode(raw), headers={"Content-Type": "text/plain"})
    clean = r.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    return base64.b64decode(clean).decode("iso-8859-1", errors="replace")

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Anon init
send(URL, envelope("0", 1, f"HKIDN:2:2+280:{BLZ}+0+0+0'HKVVB:3:3+0+0+0+{PID}+1.0'"))

# Auth init
resp = send(URL, envelope("0", 2,
    f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'HKVVB:3:3+0+0+0+{PID}+1.0'HKTAN:4:6+4+HKIDN'"))

for seg in resp.split("'"):
    if seg.startswith("HITAN"):
        print("\n=== HITAN segment ===")
        fields = seg.split("+")
        for i, f in enumerate(fields):
            if len(f) > 100:
                print(f"  Field {i}: ({len(f)} bytes) {f[:80]}...")
            else:
                print(f"  Field {i}: {f}")
        print(f"\nTotal fields: {len(fields)}")
        break

# Dialog end
send(URL, envelope("0", 3, "HKEND:2:1+0'"))
print("\nDone.")
