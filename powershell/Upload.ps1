# Macator Import-API - kompletter Upload-Flow in PowerShell.
#
#   pwsh Upload.ps1
#
# Unter Windows PowerShell 5.1 blockiert das System eigene .ps1-Dateien
# standardmaessig. Dann so starten:
#
#   powershell -ExecutionPolicy Bypass -File .\Upload.ps1
#
# Passen Sie die Variablen unten an.

# --- Variablen anpassen ----------------------------------------------
$ApiKey  = "YOUR_API_KEY"
$FeedId  = "00000000-0000-0000-0000-000000000000"
$Path    = "produkte.xlsx"
$BaseUrl = ""   # Base-URL aus dem Portal uebernehmen

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
$Hdrs = @{ Authorization = "Bearer $ApiKey" }

function Write-Step {
    param($Nr, $Text)
    Write-Host ""
    Write-Host "[$Nr/5] $Text" -ForegroundColor Cyan
}
function Write-Info { param($Text) Write-Host "      $Text" -ForegroundColor DarkGray }
function Write-Ok   { param($Text) Write-Host "      $Text" -ForegroundColor Green }

# Die API liefert bis zu 50 fehlerhafte Zeilen (mehrere Meldungen je Zeile moeglich).
# Im Terminal nur die ersten zeigen - die vollstaendige Liste steht im Portal.
function Write-Fehler {
    param($Fehler, $Color, $Max = 5)
    foreach ($e in @($Fehler | Select-Object -First $Max)) {
        $wo = if ($e.row) { "Zeile $($e.row)" } else { "Datei" }
        if ($e.column) { $wo += ", Feld $($e.column)" }
        if ($null -ne $e.value) { $wo += " ('$($e.value)')" }
        Write-Host "        $wo : $($e.message)" -ForegroundColor $Color
    }
    if ($Fehler.Count -gt $Max) {
        Write-Host "        ... und $($Fehler.Count - $Max) weitere Meldungen" -ForegroundColor $Color
    }
}

function Invoke-Api {
    param($Method, $Uri, $Body, $ContentType)
    $p = @{ Method = $Method; Uri = $Uri; Headers = $Hdrs; UseBasicParsing = $true }
    if ($ContentType) { $p.ContentType = $ContentType }
    if ($Body)        { $p.Body = $Body }
    try {
        $resp = Invoke-WebRequest @p
        $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        if (-not $text) { return $null }
        return $text | ConvertFrom-Json
    } catch {
        $resp = $_.Exception.Response
        if (-not $resp) { throw }
        $status = [int]$resp.StatusCode
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        $detail = $raw
        try {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.detail) {
                $detail = if ($parsed.detail -is [string]) { $parsed.detail }
                          else { $parsed.detail | ConvertTo-Json -Compress -Depth 5 }
            }
        } catch { }
        throw "HTTP $status - $detail"
    }
}

try {
    if (-not $BaseUrl) { throw "Bitte zuerst die Base-URL aus dem Portal in `$BaseUrl eintragen." }
    $file = Get-Item $Path
    Write-Host ""
    Write-Host "Datei: $($file.Name)  ($([math]::Round($file.Length / 1KB, 1)) KB)"
    Write-Host "Feed:  $FeedId"

    # 1 -----------------------------------------------------------------
    Write-Step 1 "Upload-URL anfordern"
    $body = @{
        feed_id   = $FeedId
        filename  = $file.Name
        file_size = $file.Length
    } | ConvertTo-Json
    $r1 = Invoke-Api -Method Post -Uri "$BaseUrl/request-upload" -Body $body -ContentType "application/json"
    $JobId = $r1.job_id
    Write-Ok "Job angelegt: $JobId"

    # 2 -----------------------------------------------------------------
    Write-Step 2 "Datei hochladen"
    Invoke-WebRequest -Method Put -Uri $r1.presigned_url -InFile $Path `
        -ContentType $r1.content_type -UseBasicParsing | Out-Null
    Write-Ok "$($file.Length) Bytes uebertragen"

    # 3 -----------------------------------------------------------------
    Write-Step 3 "Sicherheitspruefung laeuft"
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
        $s = Invoke-Api -Method Get -Uri "$BaseUrl/jobs/$JobId/scan-status"
        Write-Info "scan_status: $($s.scan_status)"
        if ($s.scan_status -in @("infected", "error")) { throw "Sicherheitspruefung fehlgeschlagen: $($s.message)" }
        if ($s.scan_status -eq "clean" -and -not $s.can_validate) {
            throw "Der Vorgang wurde serverseitig beendet: $($s.message)"
        }
        if ((Get-Date) -gt $deadline) { throw "Zeitueberschreitung bei der Sicherheitspruefung" }
    } until ($s.can_validate)
    Write-Ok "Sicherheitspruefung bestanden"

    # 4 -----------------------------------------------------------------
    Write-Step 4 "Daten pruefen"
    $v = Invoke-Api -Method Post -Uri "$BaseUrl/jobs/$JobId/validate"

    if ($v.is_duplicate) {
        Write-Host "      $($v.duplicate_message)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Kein Import erforderlich: Der Datenbestand ist unveraendert." -ForegroundColor Yellow
        exit 0
    }
    # valid=true heisst nur "mindestens eine Zeile gueltig" - errors kann trotzdem gefuellt sein
    $fehler = @($v.errors | Where-Object { $_ })
    if (-not $v.valid) {
        Write-Fehler $fehler Red
        throw "Validierung fehlgeschlagen ($($fehler.Count) Fehler)"
    }

    Write-Ok "$($v.row_count) Zeilen erkannt (Format: $($v.format))"
    if ($fehler.Count) {
        $fehlerZeilen = @($fehler | ForEach-Object { $_.row } | Where-Object { $_ } | Select-Object -Unique).Count
        Write-Host "      $fehlerZeilen von $($v.row_count) Zeilen enthalten Fehler und werden nicht importiert:" -ForegroundColor Yellow
        Write-Fehler $fehler Yellow
    }
    foreach ($w in @($v.warnings)) { if ($w) { Write-Info "Hinweis: $w" } }
    if ($v.deactivation_count) { Write-Info "$($v.deactivation_count) Angebote werden deaktiviert" }

    # 5 -----------------------------------------------------------------
    Write-Step 5 "Import freigeben"
    $r = Invoke-Api -Method Post -Uri "$BaseUrl/jobs/$JobId/submit"
    # total_items ist 0, wenn die Vorpruefung die Datei nicht vollstaendig gelesen hat
    $umfang = if ($r.total_items) { "$($r.total_items) Zeilen" } else { "Datei" }
    Write-Ok "Status: $($r.status), $umfang an den Import uebergeben"

    Write-Host ""
    Write-Host "Import gestartet. Fortschritt im Portal unter 'Import & Feeds'." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ABGEBROCHEN: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
