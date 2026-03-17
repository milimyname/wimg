#!/usr/bin/env python3
"""Fetch Comdirect transactions via FinTS — with HKSPA account discovery."""
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
print("--- Anon init ---")
send(URL, envelope("0", 1, f"HKIDN:2:2+280:{BLZ}+0+0+0'HKVVB:3:3+0+0+0+{PID}+1.0'"))

# Step 2: Auth
print("--- Auth init ---")
resp2 = send(URL, envelope("0", 2, f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'HKVVB:3:3+0+0+0+{PID}+1.0'HKTAN:4:6+4+HKIDN'"))
print(f"  Auth: {len(resp2)} bytes")

# Step 3: HKSPA to get account info
print("\n--- HKSPA (get SEPA accounts) ---")
resp3 = send(URL, envelope("0", 3, f"HKSPA:2:1'HKTAN:3:6+4+HKSPA'"))
print(f"  HKSPA response: {len(resp3)} bytes")

iban = None
konto = None
for seg in resp3.split("'"):
    if seg.startswith("HISPA"):
        print(f"\n  HISPA: {seg[:200]}")
        fields = seg.split("+")
        for i, f in enumerate(fields):
            print(f"    Field {i}: {f[:80]}")
        # HISPA usually has IBAN in field 1 or 2
        for f in fields[1:]:
            if f.startswith("DE") and len(f) >= 22:
                iban = f[:22]
            if ":" in f and not f.startswith("HISPA"):
                konto = f

    # Also check HIRMS for errors
    if seg.startswith("HIRMS") or seg.startswith("HIRMG"):
        print(f"  {seg[:120]}")

if iban:
    print(f"\n  Found IBAN: {iban}")
if konto:
    print(f"  Found Kontoverbindung: {konto}")

# Step 4: HKKAZ with the discovered account
if iban or konto:
    print("\n--- HKKAZ v5 with account ---")
    acct = konto if konto else ""
    fetch_msg = envelope("0", 4,
        f"HKKAZ:2:5+{acct}++2026-02-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'")
    resp4 = send(URL, fetch_msg)
    print(f"  Fetch response: {len(resp4)} bytes")

    for seg in resp4.split("'"):
        if seg.startswith("HIKAZ"):
            print(f"\n  ✅ Got MT940 data! ({len(seg)} bytes)")
            print(f"  First 200 chars: {seg[:200]}")
        elif seg.startswith("HIRMS") or seg.startswith("HIRMG"):
            print(f"  {seg[:120]}")
else:
    print("\n  No account found — trying HKKAZ with empty account...")
    resp4 = send(URL, envelope("0", 4,
        f"HKKAZ:2:5+++2026-02-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'"))
    for seg in resp4.split("'"):
        if seg.strip():
            print(f"  {seg[:120]}")

# Dialog end
send(URL, envelope("0", 5, "HKEND:2:1+0'"))
print("\nDone.")
