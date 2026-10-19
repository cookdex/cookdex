# Read-only: inspect metadata and direct version commands. Never run Flutter,
# rustup installers, Gradle, adb, a build, or any application data/signing reader.
param([switch]$Emulator, [switch]$Codegen)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pin = Get-Content -LiteralPath (Join-Path $root 'toolchain.json') -Raw | ConvertFrom-Json
. (Join-Path $root 'flutter/scripts/env.ps1')
$script:failures = 0
function Check([string]$name, [string]$expected, [scriptblock]$read) {
    try {
        $actual = (& $read | Out-String).Trim()
        if ($actual -ne $expected) { throw "expected $expected; found $actual" }
        Write-Output "OK $name ($expected)"
    } catch { $script:failures++; Write-Output "MISSING OR WRONG: $name. Expected $expected. Check docs/DEVELOPMENT.md." }
}
function Version([string]$exe, [string[]]$arguments, [string]$pattern) {
    $value = (& $exe @arguments 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $value -notmatch $pattern) { throw 'Version unavailable' }
    return $Matches[1]
}
# Git does not participate in app compilation: only its upstream minimum matters.
try {
    $gitVersion = Version 'git' @('--version') 'git version (\S+)'
    if ($gitVersion -notmatch '^(\d+\.\d+\.\d+)(?:\.|$)') { throw 'Unknown Git version' }
    $gitActual = [version]$Matches[1]
    if ($pin.git -notmatch '^(\d+\.\d+\.\d+)(?:\.|$)') { throw 'Unknown Git minimum' }
    if ($gitActual -lt [version]$Matches[1]) { throw 'Git is below minimum' }
    Write-Output "OK Git on PATH ($gitVersion; minimum $($pin.git))"
} catch { $script:failures++; Write-Output "MISSING OR TOO OLD: Git on PATH. Minimum $($pin.git). Check docs/DEVELOPMENT.md." }
Check 'PowerShell' $pin.powershell { $PSVersionTable.PSVersion.ToString() }
if ($pin.PSObject.Properties.Name -contains 'node') {
    Check 'Node on PATH' $pin.node { Version 'node' @('--version') 'v(\S+)' }
    Check 'npm on PATH' $pin.npm { Version 'npm.cmd' @('--version') '(\d+\.\d+\.\d+)' }
}
Check 'Python on PATH' $pin.python { Version 'python' @('--version') 'Python (\S+)' }
Check 'rustup' $pin.rustup { Version 'rustup' @('--version') 'rustup (\S+)' }
# Calling rustc through rustup could install a missing pinned toolchain. Inspect
# only an already installed compiler; report an explicit equivalent override.
$rustHome = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { Join-Path $env:USERPROFILE '.rustup' }
$rustName = if ($env:RUSTUP_TOOLCHAIN) { $env:RUSTUP_TOOLCHAIN } else { "$($pin.rust)-x86_64-pc-windows-msvc" }
if ($rustName -notmatch '-pc-windows-msvc$') { $rustName += '-x86_64-pc-windows-msvc' }
$rustDirectory = Join-Path $rustHome "toolchains/$rustName"
Check "Rust compiler ($rustName)" $pin.rust { Version (Join-Path $rustDirectory 'bin/rustc.exe') @('--version') 'rustc (\S+)' }
Check 'Cargo' $pin.rust { Version (Join-Path $rustDirectory 'bin/cargo.exe') @('--version') 'cargo (\S+)' }
foreach ($target in @('x86_64-pc-windows-msvc','aarch64-linux-android','x86_64-linux-android')) {
    Check "Rust target $target" 'installed' { if (Test-Path (Join-Path $rustDirectory "lib/rustlib/$target/lib")) { 'installed' } }
}
foreach ($component in @('rustfmt','cargo-clippy')) {
    Check "Rust component $component" 'installed' { if (Test-Path (Join-Path $rustDirectory "bin/$component.exe")) { 'installed' } }
}
Check 'Flutter SDK' $pin.flutter { (Get-Content (Join-Path $env:FLUTTER_SDK 'bin/cache/flutter.version.json') -Raw | ConvertFrom-Json).frameworkVersion }
Check 'Flutter SDK revision' $pin.flutterRevision { (& git -C $env:FLUTTER_SDK rev-parse HEAD | Out-String).Trim() }
Check 'Dart bundled with Flutter' $pin.dart { Version (Join-Path $env:FLUTTER_SDK 'bin/cache/dart-sdk/bin/dart.exe') @('--version') 'Dart SDK version: (\S+)' }
Check 'Java at JAVA_HOME' $pin.java { Version (Join-Path $env:JAVA_HOME 'bin/java.exe') @('--version') '(?:openjdk|java) (\S+)' }
Check 'Android Studio build' $pin.androidStudioBuild { (Get-Content (Join-Path (Split-Path $env:JAVA_HOME -Parent) 'build.txt') -Raw).Trim() }
$packages = @($pin.androidPackages.PSObject.Properties)
if ($Emulator) { $packages += @($pin.emulatorPackages.PSObject.Properties) }
foreach ($package in $packages) {
    Check "Android SDK $($package.Name)" $package.Value {
        $text = Get-Content (Join-Path $env:ANDROID_HOME "$($package.Name)/source.properties") -Raw
        if ($text -match '(?m)^Pkg.Revision\s*=\s*([^\r\n]+)') { $Matches[1].Trim() }
    }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = $null
Check 'Visual Studio Build Tools' $pin.visualStudio {
    $script:vs = @((& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | Out-String | ConvertFrom-Json) | Where-Object { $_.installationVersion -eq $pin.visualStudio })[0]
    $script:vs.installationVersion
}
Check 'MSVC toolset' $pin.msvc { if ($vs -and (Test-Path (Join-Path $vs.installationPath "VC/Tools/MSVC/$($pin.msvc)/bin/Hostx64/x64/cl.exe"))) { $pin.msvc } }
Check 'MSBuild' $pin.msbuild { Version (Join-Path $vs.installationPath 'MSBuild/Current/Bin/MSBuild.exe') @('-version','-nologo') '(\d+\.\d+\.\d+\.\d+)' }
Check 'Windows SDK' $pin.windowsSdk { if (Test-Path (Join-Path ${env:ProgramFiles(x86)} "Windows Kits/10/Lib/$($pin.windowsSdk)/um/x64/kernel32.lib")) { $pin.windowsSdk } }
Check 'Windows CMake' $pin.cmake { Version (Join-Path $vs.installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe') @('--version') 'cmake version (\S+)' }
Check 'Windows Ninja' $pin.ninja { Version (Join-Path $vs.installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe') @('--version') '(\S+)' }
Check 'Gradle wrapper pin' $pin.gradle {
    $text = Get-Content (Join-Path $root 'flutter/android/gradle/wrapper/gradle-wrapper.properties') -Raw
    if ($text -match 'gradle-([0-9.]+)-all.zip') { $Matches[1] }
}
foreach ($entry in @(@('com.android.application',$pin.agp),@('org.jetbrains.kotlin.android',$pin.kotlin))) {
    Check "Gradle plugin $($entry[0])" $entry[1] {
        $text = Get-Content (Join-Path $root 'flutter/android/settings.gradle.kts') -Raw
        if ($text -match ('id\("'+[regex]::Escape($entry[0])+'"\) version "([^"]+)"')) { $Matches[1] }
    }
}
if ($env:RECIPE_DEBUG_KEYSTORE) {
    Check 'Explicit dev signing key (existence only)' 'present' { if (Test-Path -LiteralPath $env:RECIPE_DEBUG_KEYSTORE -PathType Leaf) { 'present' } }
} else { Write-Output 'OK dev signing: standard Android debug key (no owner keys required)' }
Check 'Gitleaks' $pin.gitleaks { Version (Join-Path $cookdexTools "gitleaks/$($pin.gitleaks)/gitleaks.exe") @('version') '(\d+\.\d+\.\d+)' }
if ($Codegen) {
    $generator = if ($env:FRB_CODEGEN) { $env:FRB_CODEGEN } else { Join-Path $cookdexTools 'frb/bin/flutter_rust_bridge_codegen.exe' }
    Check 'FRB generator' $pin.frb { Version $generator @('--version') 'flutter_rust_bridge_codegen (\S+)' }
    Check 'cargo-expand' $pin.cargoExpand { Version (Join-Path $env:CARGO_HOME 'bin/cargo-expand.exe') @('--version') 'cargo-expand (\S+)' }
}
Write-Output "Doctor: $script:failures required checks failed. Optional emulator/codegen checks require their switches. Production secrets were not inspected."
if ($script:failures) { exit 1 }
