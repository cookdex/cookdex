# Pinned official Windows x64 scanner; no PATH or machine-wide changes.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pin = Get-Content (Join-Path $root 'toolchain.json') -Raw | ConvertFrom-Json
$tools = if ($env:COOKDEX_TOOLS) { $env:COOKDEX_TOOLS } else { Join-Path (Split-Path $root -Parent) 'cookdex-tools' }
$destination = Join-Path $tools "gitleaks/$($pin.gitleaks)"
if (Test-Path $destination) {
    $actual = & (Join-Path $destination 'gitleaks.exe') version
    if ($LASTEXITCODE -ne 0 -or $actual.Trim() -ne $pin.gitleaks) { throw 'Existing scanner does not match pin.' }
    Write-Output "Gitleaks $actual already installed."
    exit 0
}
$archive = Join-Path ([IO.Path]::GetTempPath()) ('gitleaks-' + [Guid]::NewGuid().ToString('N') + '.zip')
try {
    Invoke-WebRequest "https://github.com/gitleaks/gitleaks/releases/download/v$($pin.gitleaks)/gitleaks_$($pin.gitleaks)_windows_x64.zip" -OutFile $archive
    if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pin.gitleaksWindowsSha256) { throw 'Gitleaks archive checksum mismatch.' }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $destination
    & (Join-Path $destination 'gitleaks.exe') version
    if ($LASTEXITCODE -ne 0) { throw 'Scanner version check failed.' }
} finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive } }
