# Macator — Import API Beispiele

Lauffähige Beispiel-Scripts, um Produktdaten automatisiert über die Macator
Import-API hochzuladen — ohne Login im Portal. Geeignet für die Anbindung aus
einem ERP-System oder anderen Diensten.

Verfügbar in **Python**, **Bash (curl)** und **PowerShell**. Alle drei führen
denselben Flow aus:

1. Upload-URL anfordern
2. Produktdaten-/Katalogdatei nach Macator hochladen
3. Sicherheitscheck der hochgeladenen Daten abrufen
4. Daten validieren
5. Import freigeben

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

Er besitzt ausschließlich den Scope `import:upload` und kann nur die
Upload-Endpoints aufrufen — kein Lesezugriff auf andere Daten.

## Endpoints

| Methode | Pfad | Zweck |
| --- | --- | --- |
| `POST` | `/request-upload` | Datei einreichen, Upload-URL erhalten |
| `GET`  | `/jobs/{id}/scan-status` | Sicherheitscheck-Status abfragen |
| `POST` | `/jobs/{id}/validate` | Daten validieren |
| `POST` | `/jobs/{id}/submit` | Import auslösen |

## Quickstart

Wählen Sie Ihre Sprache und passen Sie oben im Script `API_KEY`, `FEED_ID`,
`FILE` und `BASE` an:

- [`python/upload.py`](python/upload.py) — `pip install -r python/requirements.txt && python python/upload.py`
- [`bash/upload.sh`](bash/upload.sh) — `bash bash/upload.sh` (benötigt `curl` und `jq`)
- [`powershell/Upload.ps1`](powershell/Upload.ps1) — `pwsh powershell/Upload.ps1`

## Lizenz

[MIT](LICENSE) — Sie dürfen diesen Code frei in Ihre eigenen Systeme
übernehmen und anpassen.
