# Macator Import-API — kompletter Upload-Flow in PowerShell.
#
#   pwsh Upload.ps1
#
# Passen Sie die Variablen unten an.

$ApiKey  = "YOUR_API_KEY"
$FeedId  = "00000000-0000-0000-0000-000000000000"
$Path    = "produkte.xlsx"
$BaseUrl = "https://<IHRE-PORTAL-DOMAIN>/api/v1/import"
$Hdrs    = @{ Authorization = "Bearer $ApiKey" }

# 1. Upload-URL anfordern
$body = @{
  feed_id   = $FeedId
  filename  = (Split-Path $Path -Leaf)
  file_size = (Get-Item $Path).Length
} | ConvertTo-Json

$r1 = Invoke-RestMethod -Method POST -Uri "$BaseUrl/request-upload" `
  -Headers $Hdrs -ContentType "application/json" -Body $body
$JobId = $r1.job_id

# 2. Produktdaten-/Katalogdatei nach Macator hochladen
Invoke-WebRequest -Method PUT -Uri $r1.presigned_url `
  -InFile $Path -ContentType $r1.content_type -UseBasicParsing | Out-Null

# 3. Sicherheitscheck der hochgeladenen Daten abrufen
do {
  Start-Sleep -Seconds 3
  $s = Invoke-RestMethod -Method GET -Uri "$BaseUrl/jobs/$JobId/scan-status" -Headers $Hdrs
  Write-Host "scan_status: $($s.scan_status)"
} until ($s.can_validate -or $s.scan_status -eq "infected")

# 4. Validieren
$v = Invoke-RestMethod -Method POST -Uri "$BaseUrl/jobs/$JobId/validate" -Headers $Hdrs
if (-not $v.valid) { throw "Validierung fehlgeschlagen" }
Write-Host "$($v.row_count) Zeilen erkannt"

# 5. Import freigeben
Invoke-RestMethod -Method POST -Uri "$BaseUrl/jobs/$JobId/submit" -Headers $Hdrs
