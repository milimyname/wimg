#!/usr/bin/env python3
"""Dump all segments from auth init to find account info."""
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

# Step 1: Anon
send(URL, envelope("0", 1, f"HKIDN:2:2+280:{BLZ}+0+0+0'HKVVB:3:3+0+0+0+{PID}+1.0'"))

# Step 2: Auth
resp = send(URL, envelope("0", 2, f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'HKVVB:3:3+0+0+0+{PID}+1.0'HKTAN:4:6+4+HKIDN'"))

print(f"\n=== Auth response ({len(resp)} bytes) — ALL segments ===")
for seg in resp.split("'"):
    if not seg.strip():
        continue
    header = seg.split("+")[0]
    if len(seg) > 150:
        print(f"  {header}: {seg[:150]}...")
    else:
        print(f"  {header}: {seg}")

# Look for account info in HIUPA/HIUPD
print("\n=== Looking for account data ===")
found = False
for seg in resp.split("'"):
    for prefix in ["HIUPD", "HIUPA", "HISPA", "HISPA"]:
        if seg.startswith(prefix):
            print(f"\n  {prefix}:")
            for i, f in enumerate(seg.split("+")):
                print(f"    Field {i}: {f[:80]}")
            found = True

if not found:
    print("  No account data found. Bank may require full SCA first.")
    print("  Trying HKSPA to request SEPA account info...")

    # Try HKSPA
    resp3 = send(URL, envelope("0", 3, f"HKSPA:2:1+'HKTAN:3:6+4+HKSPA'"))
    print(f"\n  HKSPA response ({len(resp3)} bytes):")
    for seg in resp3.split("'"):
        if seg.strip():
            header = seg.split("+")[0]
            print(f"    {header}: {seg[:120]}")

send(URL, envelope("0", 4, "HKEND:2:1+0'"))
print("\nDone.")
