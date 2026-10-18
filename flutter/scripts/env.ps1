# Session-only development paths; no signing-key or production-data lookup.
$ErrorActionPreference = 'Stop'
$flutterRoot = Split-Path $PSScriptRoot -Parent
$cookdexRoot = Split-Path $flutterRoot -Parent
$cookdexTools = if ($env:COOKDEX_TOOLS) { $env:COOKDEX_TOOLS } else { Join-Path (Split-Path $cookdexRoot -Parent) 'cookdex-tools' }
if (-not $env:FLUTTER_SDK) { $env:FLUTTER_SDK = Join-Path $cookdexTools 'flutter' }
if (-not $env:PUB_CACHE) { $env:PUB_CACHE = Join-Path $cookdexTools 'pub-cache' }
if (-not $env:CARGO_HOME) { $env:CARGO_HOME = Join-Path $cookdexRoot 'work/.cargo-network' }
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = Join-Path $cookdexTools 'gradle' }
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = Join-Path $env:ProgramFiles 'Android/Android Studio/jbr' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
if (-not $env:ANDROID_USER_HOME) { $env:ANDROID_USER_HOME = Join-Path $cookdexRoot 'work/flutter-android' }
if (-not $env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME = Join-Path $env:ANDROID_USER_HOME 'avd' }
$env:NDK_HOME = Join-Path $env:ANDROID_HOME 'ndk/30.0.16248370'
$env:Path = "$env:FLUTTER_SDK\bin;$env:USERPROFILE\.cargo\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
$flutterLlvm = Join-Path $env:NDK_HOME 'toolchains/llvm/prebuilt/windows-x86_64/bin'
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = Join-Path $flutterLlvm 'aarch64-linux-android24-clang.cmd'
$env:CC_aarch64_linux_android = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
$env:AR_aarch64_linux_android = Join-Path $flutterLlvm 'llvm-ar.exe'
$env:CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER = Join-Path $flutterLlvm 'x86_64-linux-android24-clang.cmd'
$env:CC_x86_64_linux_android = $env:CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER
$env:AR_x86_64_linux_android = Join-Path $flutterLlvm 'llvm-ar.exe'
function Assert-FlutterExit { if ($LASTEXITCODE -ne 0) { throw "Command failed: $LASTEXITCODE" } }
