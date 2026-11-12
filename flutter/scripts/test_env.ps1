# Process-local environment setup only; no builds, keys or device access.
$ErrorActionPreference = 'Stop'
$savedPath = $env:Path
try {
    . "$PSScriptRoot/env.ps1"
    $expected = $env:Path
    for ($iteration = 0; $iteration -lt 1000; $iteration++) {
        . "$PSScriptRoot/env.ps1"
    }
    if ($env:Path -cne $expected) { throw 'Repeated setup changed or grew PATH' }
    $toolPrefix = @("$env:FLUTTER_SDK\bin", "$env:USERPROFILE\.cargo\bin", "$env:JAVA_HOME\bin", "$env:ANDROID_HOME\platform-tools")
    $parts = $env:Path -split ';'
    for ($index = 0; $index -lt $toolPrefix.Count; $index++) {
        if ($parts[$index] -ne $toolPrefix[$index] -or @($parts | Where-Object { $_ -eq $toolPrefix[$index] }).Count -ne 1) {
            throw 'Tool precedence or multiplicity changed'
        }
    }
    'PASS: 1,000 environment setups preserve PATH exactly and retain tool precedence.'
} finally { $env:Path = $savedPath }
