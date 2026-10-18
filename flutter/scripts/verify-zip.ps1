param([string]$ArtifactsDirectory = 'artifacts/zip-verification')
. "$PSScriptRoot/env.ps1"
$fixtureRoot = Join-Path $cookdexRoot $ArtifactsDirectory
Push-Location $cookdexRoot
try {
    python tests/fixtures/zip_interop.py prepare $fixtureRoot
    Assert-FlutterExit
    cargo run --manifest-path flutter/rust/Cargo.toml --locked --offline -p cookdex-core --example zip_interop -- $fixtureRoot
    Assert-FlutterExit
    python tests/fixtures/zip_interop.py verify $fixtureRoot
    Assert-FlutterExit
} finally { Pop-Location }
