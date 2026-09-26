"""
Macator Import-API - kompletter Upload-Flow in Python.

    pip install -r requirements.txt
    python upload.py

Passen Sie API_KEY, FEED_ID, FILE_PATH und BASE unten an.

Beendet sich mit Exit-Code 0 bei Erfolg (auch wenn die Datei bereits
importiert war) und mit 1, sobald ein Schritt fehlschlaegt. Jeder Schritt
laeuft nur, wenn der vorherige erfolgreich war.
"""

import os
import sys
import time
from typing import Optional

import requests

# --- Variablen anpassen ----------------------------------------------
API_KEY = "YOUR_API_KEY"
FEED_ID = "00000000-0000-0000-0000-000000000000"
FILE_PATH = "produkte.xlsx"
BASE = ""  # Base-URL aus dem Portal uebernehmen


HEADERS = {"Authorization": f"Bearer {API_KEY}"}
SCAN_TIMEOUT_S = 90
SCAN_INTERVAL_S = 3
MAX_FEHLER_ANZEIGE = 5


class Abbruch(RuntimeError):
    """Fachlicher Abbruch mit einer Meldung, die dem Anwender etwas sagt."""


def step(nr: int, text: str) -> None:
    print(f"\n[{nr}/5] {text}")


def info(text: str) -> None:
    print(f"      {text}")


def fehler_ausgeben(fehler: list) -> None:
    """
    Gibt die ersten Zeilenfehler aus.

    Die API liefert bis zu 50 fehlerhafte Zeilen (mehrere Meldungen je Zeile
    moeglich). Im Terminal nur die ersten zeigen - die vollstaendige Liste
    steht im Portal.
    """
    for e in fehler[:MAX_FEHLER_ANZEIGE]:
        wo = f"Zeile {e['row']}" if e.get("row") else "Datei"
        if e.get("column"):
            wo += f", Feld {e['column']}"
        if e.get("value") is not None:
            wo += f" ('{e['value']}')"
        print(f"        {wo} : {e.get('message')}")
    if len(fehler) > MAX_FEHLER_ANZEIGE:
        print(f"        ... und {len(fehler) - MAX_FEHLER_ANZEIGE} weitere Meldungen")


def api(method: str, path: str, json_body: Optional[dict] = None) -> Optional[dict]:
    """
    Ruft die Import-API auf und macht die Fehlermeldung des Servers sichtbar.

    requests.raise_for_status() nennt nur den Statuscode; der eigentliche
    Grund steht im Body unter "detail" ("Datei bereits importiert",
    "Feed nicht gefunden", ...).
    """
    try:
        resp = requests.request(
            method, f"{BASE}{path}", headers=HEADERS, json=json_body, timeout=60
        )
    except requests.RequestException as e:
        raise Abbruch(f"Verbindung fehlgeschlagen: {e}") from e

    if not resp.ok:
        detail = resp.text
        try:
            payload = resp.json()
            if payload.get("detail"):
                detail = payload["detail"]
        except ValueError:
            pass
        raise Abbruch(f"HTTP {resp.status_code} - {detail}")

    return resp.json() if resp.content else None


def upload_datei(presigned_url: str, content_type: str) -> None:
    """Laedt die Datei direkt hoch. Ohne Authorization-Header - die URL ist signiert."""
    try:
        with open(FILE_PATH, "rb") as fh:
            resp = requests.put(
                presigned_url, data=fh, headers={"Content-Type": content_type}, timeout=300
            )
    except requests.RequestException as e:
        raise Abbruch(f"Upload fehlgeschlagen: {e}") from e

    if not resp.ok:
        raise Abbruch(f"Upload abgelehnt (HTTP {resp.status_code}): {resp.text[:200]}")


def warte_auf_sicherheitspruefung(job_id: str) -> None:
    deadline = time.time() + SCAN_TIMEOUT_S
    while True:
        time.sleep(SCAN_INTERVAL_S)
        s = api("GET", f"/jobs/{job_id}/scan-status") or {}
        info(f"scan_status: {s.get('scan_status')}")

        if s.get("scan_status") in ("infected", "error"):
            raise Abbruch(f"Sicherheitspruefung fehlgeschlagen: {s.get('message')}")
        # 'clean' ohne can_validate heisst: der Job wurde serverseitig beendet,
        # etwa weil ein neuerer Upload fuer denselben Feed gestartet wurde.
        if s.get("scan_status") == "clean" and not s.get("can_validate"):
            raise Abbruch(f"Der Vorgang wurde serverseitig beendet: {s.get('message')}")
        if s.get("can_validate"):
            return
        if time.time() > deadline:
            raise Abbruch("Zeitueberschreitung bei der Sicherheitspruefung")


def main() -> int:
    if not BASE:
        raise Abbruch("Bitte zuerst die Base-URL aus dem Portal in BASE eintragen.")
    if not os.path.isfile(FILE_PATH):
        print(f"Datei nicht gefunden: {FILE_PATH}", file=sys.stderr)
        return 1

    groesse = os.path.getsize(FILE_PATH)
    print(f"\nDatei: {os.path.basename(FILE_PATH)}  ({groesse / 1024:.1f} KB)")
    print(f"Feed:  {FEED_ID}")

    # 1 ---------------------------------------------------------------
    step(1, "Upload-URL anfordern")
    r1 = api(
        "POST",
        "/request-upload",
        {
            "feed_id": FEED_ID,
            "filename": os.path.basename(FILE_PATH),
            "file_size": groesse,
        },
    )
    job_id = r1["job_id"]
    info(f"Job angelegt: {job_id}")

    # 2 ---------------------------------------------------------------
    step(2, "Datei hochladen")
    upload_datei(r1["presigned_url"], r1["content_type"])
    info(f"{groesse} Bytes uebertragen")

    # 3 ---------------------------------------------------------------
    step(3, "Sicherheitspruefung laeuft")
    warte_auf_sicherheitspruefung(job_id)
    info("Sicherheitspruefung bestanden")

    # 4 ---------------------------------------------------------------
    step(4, "Daten pruefen")
    v = api("POST", f"/jobs/{job_id}/validate") or {}

    if v.get("is_duplicate"):
        info(v.get("duplicate_message") or "Inhaltsgleiche Datei bereits importiert.")
        print("\nKein Import erforderlich: Der Datenbestand ist unveraendert.")
        return 0

    # valid=true heisst nur "mindestens eine Zeile gueltig" - errors kann trotzdem gefuellt sein
    fehler = v.get("errors") or []
    if not v.get("valid"):
        fehler_ausgeben(fehler)
        raise Abbruch(f"Validierung fehlgeschlagen ({len(fehler)} Fehler)")

    info(f"{v.get('row_count')} Zeilen erkannt (Format: {v.get('format')})")
    if fehler:
        fehler_zeilen = len({e["row"] for e in fehler if e.get("row")})
        info(
            f"{fehler_zeilen} von {v.get('row_count')} Zeilen enthalten Fehler "
            "und werden nicht importiert:"
        )
        fehler_ausgeben(fehler)
    for w in v.get("warnings") or []:
        info(f"Hinweis: {w}")
    if v.get("deactivation_count"):
        info(f"{v['deactivation_count']} Angebote werden deaktiviert")

    # 5 ---------------------------------------------------------------
    step(5, "Import freigeben")
    r = api("POST", f"/jobs/{job_id}/submit") or {}
    # total_items ist 0, wenn die Vorpruefung die Datei nicht vollstaendig gelesen hat
    umfang = f"{r['total_items']} Zeilen" if r.get("total_items") else "Datei"
    info(f"Status: {r.get('status')}, {umfang} an den Import uebergeben")

    print("\nImport gestartet. Fortschritt im Portal unter 'Import & Feeds'.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Abbruch as fehler:
        print(f"\nABGEBROCHEN: {fehler}", file=sys.stderr)
        sys.exit(1)
