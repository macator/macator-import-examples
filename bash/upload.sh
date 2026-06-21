#!/usr/bin/env bash
#
# Macator Import-API — kompletter Upload-Flow mit curl + jq.
#
#   bash upload.sh
#
# Benötigt: curl, jq. Passen Sie die Variablen unten an.
set -euo pipefail

API_KEY="YOUR_API_KEY"
FEED_ID="00000000-0000-0000-0000-000000000000"
FILE="produkte.xlsx"
BASE="https://IHR-PORTAL/api/v1/import"  # vollständige Base-URL aus dem Portal übernehmen

# 1. Upload-URL anfordern
RESP=$(curl -s -X POST "$BASE/request-upload" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"feed_id\":\"$FEED_ID\",\"filename\":\"$(basename "$FILE")\",\"file_size\":$(stat -c%s "$FILE")}")
JOB_ID=$(echo "$RESP" | jq -r .job_id)
URL=$(echo "$RESP" | jq -r .presigned_url)
CT=$(echo "$RESP" | jq -r .content_type)

# 2. Produktdaten-/Katalogdatei nach Macator hochladen
curl -X PUT "$URL" -H "Content-Type: $CT" --data-binary @"$FILE"

# 3. Sicherheitscheck der hochgeladenen Daten abrufen
while :; do
  S=$(curl -s "$BASE/jobs/$JOB_ID/scan-status" -H "Authorization: Bearer $API_KEY")
  echo "scan_status: $(echo "$S" | jq -r .scan_status)"
  [ "$(echo "$S" | jq -r .can_validate)" = "true" ] && break
  sleep 3
done

# 4. Validieren
curl -X POST "$BASE/jobs/$JOB_ID/validate" -H "Authorization: Bearer $API_KEY"

# 5. Import freigeben
curl -X POST "$BASE/jobs/$JOB_ID/submit" -H "Authorization: Bearer $API_KEY"
