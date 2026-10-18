. "$PSScriptRoot/env.ps1"
if (-not $env:FRB_CODEGEN) { $env:FRB_CODEGEN = Join-Path $cookdexTools 'frb/bin/flutter_rust_bridge_codegen.exe' }
$env:Path = "$(Join-Path $env:CARGO_HOME 'bin');$env:Path"
$env:CARGO_NET_OFFLINE = 'true'
if ((& $env:FRB_CODEGEN --version) -ne 'flutter_rust_bridge_codegen 2.13.0') { throw 'FRB generator 2.13.0 is required.' }
Push-Location $flutterRoot
try {
    flutter pub get --offline
    Assert-FlutterExit
    & $env:FRB_CODEGEN generate
    Assert-FlutterExit
    # Freezed emits format-off blank lines with trailing spaces. Normalize only
    # trailing whitespace as part of generation so git diff --check stays useful.
    $generatedPath = Join-Path $flutterRoot 'lib/src/rust/api.freezed.dart'
    $generatedText = [System.IO.File]::ReadAllText($generatedPath)
    [System.IO.File]::WriteAllText($generatedPath, [regex]::Replace($generatedText, '(?m)[ \t]+(?=\r?$)', ''))
    cargo fmt --manifest-path rust/Cargo.toml --all
    Assert-FlutterExit
} finally { Pop-Location }
