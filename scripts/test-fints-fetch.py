#!/usr/bin/env python3
"""Test HKKAZ with Comdirect — find the right account format."""
import base64, getpass, requests, sys

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

# Step 1: Anon init
print("\n--- Step 1: Anon init ---")
resp1 = send(URL, envelope("0", 1, f"HKIDN:2:2+280:{BLZ}+0+0+0'HKVVB:3:3+0+0+0+{PID}+1.0'"))

# Step 2: Auth init
print("--- Step 2: Auth init ---")
resp2 = send(URL, envelope("0", 2, f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'HKVVB:3:3+0+0+0+{PID}+1.0'HKTAN:4:6+4+HKIDN'"))

# Extract HIUPD (account info)
print("\n=== Account info from UPD ===")
for seg in resp2.split("'"):
    if seg.startswith("HIUPD"):
        fields = seg.split("+")
        print(f"  HIUPD fields:")
        for i, f in enumerate(fields):
            print(f"    {i}: {f[:80]}")
        # Field 1 = Kontoverbindung DEG, Field 2 = IBAN
        if len(fields) >= 3:
            konto = fields[1]  # e.g., "1234567::280:20041177"
            iban = fields[2]    # e.g., "DE..."
            print(f"\n  Kontoverbindung: {konto}")
            print(f"  IBAN: {iban}")

# Step 3: Fetch with HKKAZ v5 using the account from UPD
print("\n--- Step 3: HKKAZ v5 ---")
# Try with the Kontoverbindung from HIUPD
for seg in resp2.split("'"):
    if seg.startswith("HIUPD"):
        fields = seg.split("+")
        if len(fields) >= 3:
            konto_verb = fields[1]
            print(f"Using Kontoverbindung: {konto_verb}")

            fetch_msg = envelope("0", 3,
                f"HKKAZ:2:5+{konto_verb}++2026-02-01+2026-03-17++'HKTAN:3:6+4+HKKAZ'")
            print(f"Message: {fetch_msg[:100]}...")
            resp3 = send(URL, fetch_msg)

            print(f"\nResponse ({len(resp3)} bytes):")
            for s in resp3.split("'"):
                if s.strip():
                    print(f"  {s[:120]}")

            if "HIKAZ" in resp3:
                print("\n✅ Got MT940 data!")
            elif "9050" in resp3:
                print("\n❌ Error in message")
            break

# Dialog end
send(URL, envelope("0", 4, "HKEND:2:1+0'"))
print("\nDone.")
