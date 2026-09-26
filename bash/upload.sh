#!/usr/bin/env bash
#
# Macator Import-API - kompletter Upload-Flow mit curl + jq.
#
#   bash upload.sh
#
# Benoetigt: curl, jq. Passen Sie die Variablen unten an.
#
# Beendet sich mit Exit-Code 0 bei Erfolg (auch wenn die Datei bereits
# importiert war) und mit 1, sobald ein Schritt fehlschlaegt. Jeder Schritt
# laeuft nur, wenn der vorherige erfolgreich war.
set -euo pipefail

# --- Variablen anpassen ----------------------------------------------
API_KEY="YOUR_API_KEY"
FEED_ID="00000000-0000-0000-0000-000000000000"
FILE="produkte.xlsx"
BASE=""   # Base-URL aus dem Portal uebernehmen

SCAN_TIMEOUT_S=90
SCAN_INTERVAL_S=3

step() { printf '\n[%s/5] %s\n' "$1" "$2"; }
info() { printf '      %s\n' "$1"; }

abbruch() {
  printf '\nABGEBROCHEN: %s\n' "$1" >&2
  exit 1
}

# Ruft die Import-API auf und macht die Fehlermeldung des Servers sichtbar:
# curl allein liefert bei 4xx nur den Body ohne Statuscode, deshalb wird der
# Code angehaengt und getrennt ausgewertet.
api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" "$BASE$path"
              -H "Authorization: Bearer $API_KEY"
              -w $'\n%{http_code}')
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  local out code payload detail
  if ! out=$(curl "${args[@]}" 2>&1); then
    abbruch "Verbindung fehlgeschlagen: $out"
  fi

  code=${out##*$'\n'}
  payload=${out%$'\n'*}

  if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
    detail=$(printf '%s' "$payload" | jq -r 'if type == "object" then (.detail // .error // empty) else empty end' 2>/dev/null || true)
    [ -z "$detail" ] && detail="$payload"
    abbruch "HTTP $code - $detail"
  fi

  printf '%s' "$payload"
}

# Die API liefert bis zu 50 fehlerhafte Zeilen (mehrere Meldungen je Zeile
# moeglich). Im Terminal nur die ersten zeigen - die vollstaendige Liste
# steht im Portal. $1 = Antwort von validate.
MAX_FEHLER_ANZEIGE=5
fehler_ausgeben() {
  printf '%s' "$1" | jq -r --argjson max "$MAX_FEHLER_ANZEIGE" --arg q "'" '
    (.errors // []) as $e
    | ($e[:$max][]
       | (if .row then "Zeile \(.row)" else "Datei" end)
         + (if .column then ", Feld \(.column)" else "" end)
         + (if .value != null then " (\($q)\(.value)\($q))" else "" end)
         + " : " + .message),
      (if ($e | length) > $max then "... und \(($e | length) - $max) weitere Meldungen" else empty end)
  ' | while IFS= read -r zeile; do printf '        %s\n' "$zeile"; done
}

# stat unterscheidet sich zwischen GNU und BSD/macOS - wc ist ueberall gleich.
dateigroesse() { wc -c < "$1" | tr -d '[:space:]'; }

[ -n "$BASE" ] || abbruch "Bitte zuerst die Base-URL aus dem Portal in BASE eintragen."
[ -f "$FILE" ] || abbruch "Datei nicht gefunden: $FILE"
command -v jq >/dev/null 2>&1 || abbruch "jq ist nicht installiert"

SIZE=$(dateigroesse "$FILE")
printf '\nDatei: %s  (%s Bytes)\n' "$(basename "$FILE")" "$SIZE"
printf 'Feed:  %s\n' "$FEED_ID"

# 1 -------------------------------------------------------------------
step 1 "Upload-URL anfordern"
REQ=$(jq -nc --arg f "$FEED_ID" --arg n "$(basename "$FILE")" --argjson s "$SIZE" \
  '{feed_id: $f, filename: $n, file_size: $s}')
R1=$(api POST "/request-upload" "$REQ")
JOB_ID=$(printf '%s' "$R1" | jq -r .job_id)
PUT_URL=$(printf '%s' "$R1" | jq -r .presigned_url)
CT=$(printf '%s' "$R1" | jq -r .content_type)
info "Job angelegt: $JOB_ID"

# 2 -------------------------------------------------------------------
step 2 "Datei hochladen"
# ohne Authorization-Header - die Upload-URL ist bereits signiert
PUT_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$PUT_URL" \
  -H "Content-Type: $CT" --data-binary @"$FILE") || abbruch "Upload fehlgeschlagen"
if [ "$PUT_CODE" -lt 200 ] || [ "$PUT_CODE" -ge 300 ]; then
  abbruch "Upload abgelehnt (HTTP $PUT_CODE)"
fi
info "$SIZE Bytes uebertragen"

# 3 -------------------------------------------------------------------
step 3 "Sicherheitspruefung laeuft"
DEADLINE=$(( $(date +%s) + SCAN_TIMEOUT_S ))
while :; do
  sleep "$SCAN_INTERVAL_S"
  S=$(api GET "/jobs/$JOB_ID/scan-status")
  SCAN=$(printf '%s' "$S" | jq -r .scan_status)
  CAN=$(printf '%s' "$S" | jq -r .can_validate)
  MSG=$(printf '%s' "$S" | jq -r '.message // ""')
  info "scan_status: $SCAN"

  case "$SCAN" in
    infected|error) abbruch "Sicherheitspruefung fehlgeschlagen: $MSG" ;;
  esac
  # 'clean' ohne can_validate heisst: der Job wurde serverseitig beendet,
  # etwa weil ein neuerer Upload fuer denselben Feed gestartet wurde.
  if [ "$SCAN" = "clean" ] && [ "$CAN" != "true" ]; then
    abbruch "Der Vorgang wurde serverseitig beendet: $MSG"
  fi
  [ "$CAN" = "true" ] && break
  [ "$(date +%s)" -gt "$DEADLINE" ] && abbruch "Zeitueberschreitung bei der Sicherheitspruefung"
done
info "Sicherheitspruefung bestanden"

# 4 -------------------------------------------------------------------
step 4 "Daten pruefen"
V=$(api POST "/jobs/$JOB_ID/validate")

if [ "$(printf '%s' "$V" | jq -r '.is_duplicate // false')" = "true" ]; then
  info "$(printf '%s' "$V" | jq -r '.duplicate_message // "Inhaltsgleiche Datei bereits importiert."')"
  printf '\nKein Import erforderlich: Der Datenbestand ist unveraendert.\n'
  exit 0
fi

# valid=true heisst nur "mindestens eine Zeile gueltig" - errors kann trotzdem gefuellt sein
ANZ=$(printf '%s' "$V" | jq -r '(.errors // []) | length')
if [ "$(printf '%s' "$V" | jq -r '.valid // false')" != "true" ]; then
  fehler_ausgeben "$V"
  abbruch "Validierung fehlgeschlagen ($ANZ Fehler)"
fi

info "$(printf '%s' "$V" | jq -r '"\(.row_count) Zeilen erkannt (Format: \(.format))"')"
if [ "$ANZ" -gt 0 ]; then
  info "$(printf '%s' "$V" | jq -r '
    "\([.errors[] | .row | select(. != null)] | unique | length) von \(.row_count) Zeilen enthalten Fehler und werden nicht importiert:"')"
  fehler_ausgeben "$V"
fi
printf '%s' "$V" | jq -r '(.warnings // [])[]' | while IFS= read -r w; do
  [ -n "$w" ] && info "Hinweis: $w"
done
DEAKT=$(printf '%s' "$V" | jq -r '.deactivation_count // 0')
if [ "$DEAKT" != "0" ] && [ "$DEAKT" != "null" ]; then
  info "$DEAKT Angebote werden deaktiviert"
fi

# 5 -------------------------------------------------------------------
step 5 "Import freigeben"
R=$(api POST "/jobs/$JOB_ID/submit")
# total_items ist 0, wenn die Vorpruefung die Datei nicht vollstaendig gelesen hat
info "$(printf '%s' "$R" | jq -r '
  "Status: \(.status), "
  + (if (.total_items // 0) > 0 then "\(.total_items) Zeilen" else "Datei" end)
  + " an den Import uebergeben"')"

printf "\nImport gestartet. Fortschritt im Portal unter 'Import & Feeds'.\n"
