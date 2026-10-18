. "$PSScriptRoot/env.ps1"
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Out-String).Trim()
$c9Cmake = Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
if (-not (Test-Path -LiteralPath $c9Cmake)) { $c9Cmake = (Get-Command cmake -ErrorAction Stop).Source }
$c9Build = Join-Path $cookdexRoot 'artifacts/c9/http-build'
& $c9Cmake -S (Join-Path $flutterRoot 'windows/tests') -B $c9Build -A x64
Assert-FlutterExit
& $c9Cmake --build $c9Build --config Debug
Assert-FlutterExit
python (Join-Path $flutterRoot 'windows/tests/http_server.py') (Join-Path $c9Build 'Debug/c9_http_test.exe')
Assert-FlutterExit
