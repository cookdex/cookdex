# Distributed in a versioned package. Dev packaging selects its own link name.
param([switch]$NonInteractive)
$ErrorActionPreference = 'Stop'
$shortcutName = 'cookdex'
try {
$executable = Join-Path $PSScriptRoot 'cookdex.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Keep this script beside cookdex.exe.' }
$parent = Split-Path $PSScriptRoot -Parent
$path = Join-Path $parent "$shortcutName.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($path)
if ((Test-Path -LiteralPath $path) -and $shortcut.TargetPath -and
    -not $shortcut.TargetPath.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Existing shortcut points outside this delivery directory; keep it and choose another location.'
}
$shortcut.TargetPath = $executable
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = "$executable,0"
$shortcut.Description = $shortcutName
$shortcut.Save()
if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
    $shell.CreateShortcut($path).TargetPath -ne $executable) {
    throw "Windows did not save the expected shortcut at $path"
}
Write-Output "Shortcut ready: $path"
Write-Output 'It is beside the versioned folder, not on your Desktop. You can move it to your Desktop.'
} catch {
    Write-Host "Could not create the shortcut: $($_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    if (-not $NonInteractive) { Read-Host 'Press Enter to close this window' | Out-Null }
}
