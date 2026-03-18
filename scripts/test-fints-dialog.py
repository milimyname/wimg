#!/usr/bin/env python3
"""Test FinTS dialog flow matching the Zig implementation.

Flow: sync dialog (sec_func=999, HKSYN) → get system_id → auth dialog (sec_func=902) → HKKAZ
"""
import base64, getpass, requests, datetime

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

def send(url, msg):
    raw = msg.encode("iso-8859-1")
    r = requests.post(url, data=base64.b64encode(raw), headers={"Content-Type": "text/plain"})
    clean = r.content.decode("iso-8859-1").replace("\n", "").replace("\r", "")
    return base64.b64decode(clean).decode("iso-8859-1", errors="replace")

def envelope(did, num, inner):
    """Bare HNHBK/HNHBS envelope."""
    trailer = f"HNHBS:{inner.count(chr(39))+2}:1+{num}'"
    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{inner}{trailer}"

def auth_envelope(did, num, kennung, pin, inner_segments, sec_ref="1234567", sec_func="999", system_id="0"):
    """HNHBK + HNVSK + HNVSD(HNSHK + segments + HNSHA) + HNHBS envelope."""
    now = datetime.datetime.now()
    date_str = now.strftime("%Y%m%d")
    time_str = now.strftime("%H%M%S")

    # HNSHK (signature header) — seg num 2
    hnshk = f"HNSHK:2:4+PIN:1+{sec_func}+{sec_ref}+1+1+1::{system_id}+1+1:{date_str}:{time_str}+1:999:1+6:10:16+280:{BLZ}:{kennung}:S:0:0'"

    # HNSHA (signature footer with PIN)
    inner_seg_count = inner_segments.count("'")
    hnsha_num = 2 + inner_seg_count + 1  # HNSHK + inner segments + HNSHA
    hnsha = f"HNSHA:{hnsha_num}:2+{sec_ref}++{pin}'"

    # Inner data (inside HNVSD)
    inner_data = hnshk + inner_segments + hnsha
    inner_len = len(inner_data)

    # HNVSK (security header - dummy encryption for PIN/TAN)
    null_key = "\x00" * 8
    hnvsk = f"HNVSK:998:3+PIN:1+998+1+1::{system_id}+1:{date_str}:{time_str}+2:2:13:@8@{null_key}:5:1+280:{BLZ}:{kennung}:V:0:0+0'"

    # HNVSD (security data wrapper)
    hnvsd = f"HNVSD:999:1+@{inner_len}@{inner_data}'"

    sec_inner = hnvsk + hnvsd
    # HNHBS seg number = count of inner segments inside HNVSD + 2 (HNVSK + HNVSD) + 1
    hnhbs_num = hnsha_num + 1
    trailer = f"HNHBS:{hnhbs_num}:1+{num}'"

    hp = "HNHBK:1:3+"
    hs = f"+300+{did}+{num}'"
    total = len(hp) + 12 + len(hs) + len(sec_inner) + len(trailer)
    return f"{hp}{total:012d}{hs}{sec_inner}{trailer}"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

# Step 1: Sync dialog (sec_func=999, HKSYN to get system_id)
print("\n=== Step 1: Sync dialog (HKSYN, sec_func=999) ===")
sync_inner = (
    f"HKIDN:3:2+280:{BLZ}+{kennung}+0+1'"
    f"HKVVB:4:3+0+0+0+{PID}+1.0'"
    f"HKSYN:5:3+0'"
)
msg1 = auth_envelope("0", 1, kennung, pin, sync_inner, sec_func="999", system_id="0")
resp1 = send(URL, msg1)

hnhbk1 = resp1.split("'")[0]
fields1 = hnhbk1.split("+")
dialog_id = fields1[3]
print(f"HNHBK: {hnhbk1}")
print(f"  dialog_id = '{dialog_id}'")

# Extract system_id from HISYN
system_id = "0"
for seg in resp1.split("'"):
    if seg.startswith("HISYN"):
        fields = seg.split("+")
        if len(fields) > 1:
            system_id = fields[1]
            print(f"  system_id = '{system_id}'")
    if seg.startswith("HIRMG") or seg.startswith("HIRMS"):
        print(f"  {seg[:200]}")

# End sync dialog
if dialog_id != "0":
    end_inner = f"HKEND:3:1+{dialog_id}'"
    msg_end = auth_envelope(dialog_id, 2, kennung, pin, end_inner, sec_ref="4567890", sec_func="999", system_id="0")
    send(URL, msg_end)
    print("  Sync dialog ended.")

if system_id == "0":
    print("\n*** ERROR: No system_id from sync ***")
else:
    # Step 2: Auth dialog with real TAN method (sec_func=902)
    print(f"\n=== Step 2: Auth dialog (sec_func=902, system_id={system_id}) ===")
    auth_inner = (
        f"HKIDN:3:2+280:{BLZ}+{kennung}+{system_id}+1'"
        f"HKVVB:4:3+0+0+0+{PID}+1.0'"
        f"HKTAN:5:6+4+HKIDN'"
    )
    msg2 = auth_envelope("0", 1, kennung, pin, auth_inner, sec_ref="2345678", sec_func="902", system_id=system_id)
    resp2 = send(URL, msg2)

    hnhbk2 = resp2.split("'")[0]
    fields2 = hnhbk2.split("+")
    dialog_id2 = fields2[3]
    print(f"HNHBK: {hnhbk2}")
    print(f"  dialog_id = '{dialog_id2}'")

    for seg in resp2.split("'"):
        if seg.startswith(("HIRMG", "HIRMS", "HITAN")):
            print(f"  {seg[:200]}")

    if dialog_id2 != "0":
        print(f"\n  Auth dialog established! Ready for HKKAZ.")
        # End dialog
        end_inner = f"HKEND:3:1+{dialog_id2}'"
        msg_end2 = auth_envelope(dialog_id2, 2, kennung, pin, end_inner, sec_ref="4567890", sec_func="902", system_id=system_id)
        send(URL, msg_end2)
    else:
        print("\n*** ERROR: Auth dialog failed ***")

print("\nDone.")
