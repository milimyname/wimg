import logging
import sys
import datetime
from fints.client import FinTS3PinTanClient

logger = logging.getLogger('fints')
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.DEBUG)
logger.addHandler(handler)

client = FinTS3PinTanClient(
    "20041177",
    "46236380",
    "191819",
    "https://fints.comdirect.de/fints",
    product_id="F7C4049477F6136957A46EC28"
)

client.system_id = "DEc3N2PD/ZwBAACkKjPRyAWCCgQA"
client.bpd = {"dummy": "bpd"}
client.upd = {"dummy": "upd"}

# We need to mock accounts to fetch statements
from fints.models import SEPAAccount
account = SEPAAccount("DE12345678901234567890", "20041177", "46236380")

try:
    client.get_transactions(account, datetime.date(2026, 1, 1), datetime.date(2026, 3, 18))
except Exception as e:
    print("Exception:", e)
