#!/usr/bin/env python3
"""Use python-fints library to see the exact HNVSK/HNVSD wire format."""
import logging, getpass, sys
from datetime import date

# Enable DEBUG logging to see raw FinTS messages
logging.basicConfig(level=logging.DEBUG, format='%(name)s: %(message)s')

try:
    from fints.client import FinTS3PinTanClient
    from fints.utils import minimal_interactive_cli_bootstrap
except ImportError:
    print("Install python-fints first: pip3 install fints")
    sys.exit(1)

BLZ = "20041177"
URL = "https://fints.comdirect.de/fints"
PID = "F7C4049477F6136957A46EC28"

kennung = input("Kennung: ")
pin = getpass.getpass("PIN: ")

f = FinTS3PinTanClient(BLZ, kennung, pin, URL, product_id=PID)

minimal_interactive_cli_bootstrap(f)

with f:
    if f.init_tan_response:
        print(f"\nTAN required: {f.init_tan_response.challenge}")
        tan = input("TAN: ")
        f.send_tan(f.init_tan_response, tan)

    accounts = f.get_sepa_accounts()
    print(f"\nAccounts: {accounts}")

    if accounts:
        statements = f.get_transactions(accounts[0], date(2025, 12, 18), date(2026, 3, 18))
        print(f"\nTransactions: {len(statements)}")
        for s in statements[:5]:
            print(f"  {s.data.get('date', '?')} {s.data.get('amount', '?')} {s.data.get('purpose', '?')}")
