# Macator — Import API Beispiele

Lauffähige Beispiel-Scripts, um Produktdaten automatisiert über die Import-API
von [www.macator.com](https://www.macator.com) hochzuladen — ohne Login im
Portal. Geeignet für die Anbindung aus einem ERP-System oder anderen Diensten.

Verfügbar in **Python**, **Bash (curl)** und **PowerShell**. Alle drei führen
denselben Flow aus:

1. Upload-URL anfordern
2. Produktdaten-/Katalogdatei nach Macator hochladen
3. Sicherheitsprüfung der hochgeladenen Daten abrufen
4. Daten validieren
5. Import freigeben

Jeder Schritt läuft nur, wenn der vorherige erfolgreich war. Schlägt einer
fehl, geben die Scripts die Meldung des Servers im Klartext aus und brechen
ab — der Import wird dann nicht ausgelöst. Ist die Datei inhaltlich
unverändert, endet der Lauf nach Schritt 4 mit einem Hinweis statt mit einem
Fehler.

Enthält die Datei nur einzelne fehlerhafte Zeilen, zeigen die Scripts in
Schritt 4 deren Anzahl und die ersten Meldungen an und geben den Import
trotzdem frei: Übernommen werden die gültigen Zeilen, die fehlerhaften werden
übersprungen. Bei Voll-Feeds gehen die bisherigen Angebote dieser Zeilen
dabei offline. Nach Schritt 5 läuft der Import im Hintergrund weiter — das
Ergebnis und die vollständige Fehlerliste stehen im Portal unter
*Import & Feeds*.

## Voraussetzungen

| Was | Wo zu finden |
| --- | --- |
| **API-Key** | Portal → API-Keys → *Neuen API-Key erstellen*. Der Key wird nur **einmal** angezeigt — sicher speichern. |
| **Feed-ID** | Portal → Feed Management → Detail-Ansicht des jeweiligen Feeds. |
| **Base-URL** | Im Portal angezeigt — Ihre Portal-Adresse gefolgt von `/api/v1/import`. |

Der Key wird bei jeder Anfrage als HTTP-Header gesetzt:

```
Authorization: Bearer YOUR_API_KEY
```

Er besitzt ausschließlich den Scope `import:upload`. Damit lassen sich Daten
einliefern (Import): Angebote, Statistiken, Konto- und Firmendaten sind über
den Key weder abrufbar noch änderbar.

## Endpoints

| Methode | Pfad | Zweck |
| --- | --- | --- |
| `POST` | `/request-upload` | Datei einreichen, Upload-URL erhalten |
| `GET`  | `/jobs/{id}/scan-status` | Status der Sicherheitsprüfung abfragen |
| `POST` | `/jobs/{id}/validate` | Daten validieren |
| `POST` | `/jobs/{id}/submit` | Import auslösen |

## Quickstart

Wählen Sie Ihre Sprache und passen Sie oben im Script `API_KEY`, `FEED_ID`,
`FILE` und `BASE` an:

- [`python/upload.py`](python/upload.py) — `pip install -r python/requirements.txt && python python/upload.py`
- [`bash/upload.sh`](bash/upload.sh) — `bash bash/upload.sh` (benötigt `curl` und `jq`)
- [`powershell/Upload.ps1`](powershell/Upload.ps1) — `pwsh powershell/Upload.ps1`

## Über Macator

Macator ist der Marktplatz für industrielle Ersatzteile. Alles Weitere zur
Plattform, zum Angebot und zur Anbindung als Händler finden Sie auf
**[www.macator.com](https://www.macator.com)**.

## Lizenz

[MIT](LICENSE) — Sie dürfen diesen Code frei in Ihre eigenen Systeme
übernehmen und anpassen.
