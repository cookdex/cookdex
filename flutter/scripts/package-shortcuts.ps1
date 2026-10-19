# Package helper generation only; never runs the helper or launches the app.
function Write-CookdexPackageShortcuts {
    param([Parameter(Mandatory)][string]$Bundle, [switch]$Production)
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'create-production-shortcut.ps1'))
    $declaration = '$shortcutName = ''cookdex'''
    if ([regex]::Matches($template, [regex]::Escape($declaration)).Count -ne 1) {
        throw 'Shortcut template declaration changed; review package generation.'
    }
    if (-not $Production) {
        $template = $template.Replace($declaration, '$shortcutName = ''cookdex-dev''')
    }
    [IO.File]::WriteAllText((Join-Path $Bundle 'Create shortcut.ps1'), $template, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'create-production-shortcut.cmd') -Destination (Join-Path $Bundle 'Create shortcut.cmd')
}
