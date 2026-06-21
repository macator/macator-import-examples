"""
Macator Import-API — kompletter Upload-Flow in Python.

    pip install -r requirements.txt
    python upload.py

Passen Sie API_KEY, FEED_ID, FILE_PATH und BASE unten an.
"""

import os
import time
import requests

API_KEY   = "YOUR_API_KEY"
FEED_ID   = "00000000-0000-0000-0000-000000000000"
FILE_PATH = "produkte.xlsx"
BASE      = "https://<IHRE-PORTAL-DOMAIN>/api/v1/import"
HEADERS   = {"Authorization": f"Bearer {API_KEY}"}

# 1. Upload-URL anfordern
resp = requests.post(
    f"{BASE}/request-upload",
    headers=HEADERS,
    json={
        "feed_id": FEED_ID,
        "filename": os.path.basename(FILE_PATH),
        "file_size": os.path.getsize(FILE_PATH),
    },
)
resp.raise_for_status()
data = resp.json()
job_id = data["job_id"]

# 2. Produktdaten-/Katalogdatei nach Macator hochladen
with open(FILE_PATH, "rb") as f:
    put = requests.put(
        data["presigned_url"],
        data=f.read(),
        headers={"Content-Type": data["content_type"]},
    )
    put.raise_for_status()

# 3. Sicherheitscheck der hochgeladenen Daten abrufen (max 90s)
deadline = time.time() + 90
while time.time() < deadline:
    s = requests.get(f"{BASE}/jobs/{job_id}/scan-status", headers=HEADERS).json()
    print("scan_status:", s.get("scan_status"))
    if s.get("can_validate"):
        break
    if s.get("scan_status") in ("infected", "error"):
        raise RuntimeError(f"Scan-Fehler: {s}")
    time.sleep(3)
else:
    raise TimeoutError("Scan-Timeout")

# 4. Validieren
v = requests.post(f"{BASE}/jobs/{job_id}/validate", headers=HEADERS).json()
if not v.get("valid"):
    raise RuntimeError(f"Validierung fehlgeschlagen: {v.get('errors')}")
print(f"{v.get('row_count')} Zeilen erkannt")

# 5. Import freigeben
result = requests.post(f"{BASE}/jobs/{job_id}/submit", headers=HEADERS).json()
print("Import gestartet:", result)
