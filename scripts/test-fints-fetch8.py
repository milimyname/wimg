#!/usr/bin/env python3
"""Try HKKAZ with different account/date formats."""
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
            print(f"    ✅ HIKAZ! ({len(seg)} bytes)")
    return decoded, did

def envelope(did, num, inner):
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

_, did = send(URL, envelope("0", 1,
    f"HKIDN:2:2+280:{BLZ}+{kennung}+0+1'"
    f"HKVVB:3:3+0+0+0+{PID}+1.0'"
    f"HKTAN:4:6+4+HKIDN'"), "auth")

n = 2
tests = [
    # Various account + date combos
    ("v5, explicit 0 subacct", f"HKKAZ:2:5+{kennung}:0:280:{BLZ}+N+20260301+20260317++'"),
    ("v5, J for all", f"HKKAZ:2:5+{kennung}::280:{BLZ}+J+20260301+20260317++'"),
    ("v5, no dates", f"HKKAZ:2:5+{kennung}::280:{BLZ}+N++++'"),
    ("v5, empty subacct, N", f"HKKAZ:2:5+{kennung}::280:{BLZ}+N+20260301+20260317++'"),
    # python-fints style (Account2.from_sepa_account typically uses Kontonummer from IBAN)
    # Comdirect Kontonummer might be different from Zugangsnummer
    ("v5, acct=Ktonr from IBAN", f"HKKAZ:2:5+{kennung}::280:20041177+N+20260301+20260317++'"),
]

for label, inner in tests:
    print(f"\n--- {label} ---")
    print(f"  Msg: {inner[:100]}")
    send(URL, envelope(did, n, inner), label)
    n += 1

send(URL, envelope(did, n, f"HKEND:2:1+{did}'"), "end")
print("\nDone.")
