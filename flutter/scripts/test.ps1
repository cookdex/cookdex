param([switch]$SkipWindowsNative,[switch]$InMemoryJob)
. "$PSScriptRoot/env.ps1"
if (-not $InMemoryJob) {
    $out = Join-Path $cookdexRoot 'artifacts/test-memory'
    New-Item -ItemType Directory -Force $out | Out-Null
    $log = Join-Path $out ("flutter-" + (Get-Date -Format yyyyMMdd-HHmmssfff) + ".json")
    $extra = if ($SkipWindowsNative) { @('-SkipWindowsNative') } else { @() }
    & python "$PSScriptRoot/guard_test_memory.py" --log $log -- (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -InMemoryJob @extra
    if ($LASTEXITCODE -ne 0) { throw "Test job stopped; inspect $log and the test output." }
    return
}
& "$PSScriptRoot/test_env.ps1"
if (Test-Path -LiteralPath "$PSScriptRoot/profile-app.ps1") {
    & "$PSScriptRoot/test_profile_adb.ps1"
}
if (Test-Path (Join-Path $cookdexRoot 'scripts/test-maintenance.ps1')) {
    & (Join-Path $cookdexRoot 'scripts/test-maintenance.ps1')
}
& "$PSScriptRoot/test-release-tooling.ps1"
Push-Location $flutterRoot
try {
    cargo fmt --manifest-path rust/Cargo.toml --all --check
    Assert-FlutterExit
    cargo test --manifest-path rust/Cargo.toml --locked --offline
    Assert-FlutterExit
    flutter pub get --offline
    Assert-FlutterExit
    flutter analyze
    Assert-FlutterExit
    flutter test --concurrency=1 test
    Assert-FlutterExit
    if ($SkipWindowsNative) { return }
    cargo build --manifest-path rust/Cargo.toml --release --locked --offline -p cookdex-core-probe -p cookdex-bridge
    Assert-FlutterExit
    flutter test integration_test/core_probe_test.dart -d windows "--dart-define=COOKDEX_TEST_PROBE_LIBRARY=$flutterRoot/rust/target/release/cookdex_core_probe.dll"
    Assert-FlutterExit
    flutter test integration_test/c3_bridge_test.dart -d windows
    Assert-FlutterExit
    flutter test integration_test/pairing_qr_test.dart -d windows
    Assert-FlutterExit
    & "$PSScriptRoot/verify-http.ps1"
} finally { Pop-Location }
