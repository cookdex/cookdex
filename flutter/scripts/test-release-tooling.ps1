# Host-only tests. Uses temporary synthetic signing material, never owner keys.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
. "$PSScriptRoot/release-signing.ps1"
& python -m unittest discover -s $PSScriptRoot -p 'test_package_hygiene.py'
Assert-FlutterExit
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cookdex-signing-test-' + [Guid]::NewGuid().ToString('N'))
$previousPassword = $env:COOKDEX_KEYTOOL_PASSWORD
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    . "$PSScriptRoot/package-shortcuts.ps1"
    # Dummy executable files only: creating .lnk files never executes them.
    $productionFolder = Join-Path $testRoot 'production'
    $devFolder = Join-Path $testRoot 'development'
    foreach ($folder in @($productionFolder, $devFolder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
        'synthetic non-executable fixture' | Set-Content (Join-Path $folder 'cookdex.exe')
    }
    Write-CookdexPackageShortcuts -Bundle $productionFolder -Production
    Write-CookdexPackageShortcuts -Bundle $devFolder
    & (Join-Path $productionFolder 'Create shortcut.ps1') -NonInteractive | Out-Null
    $productionShortcut = Join-Path $testRoot 'cookdex.lnk'
    $productionHash = (Get-FileHash -LiteralPath $productionShortcut).Hash
    & (Join-Path $devFolder 'Create shortcut.ps1') -NonInteractive | Out-Null
    $devShortcut = Join-Path $testRoot 'cookdex-dev.lnk'
    $shell = New-Object -ComObject WScript.Shell
    if ((Get-FileHash -LiteralPath $productionShortcut).Hash -ne $productionHash -or
        $shell.CreateShortcut($productionShortcut).TargetPath -ne (Join-Path $productionFolder 'cookdex.exe') -or
        $shell.CreateShortcut($devShortcut).TargetPath -ne (Join-Path $devFolder 'cookdex.exe') -or
        $shell.CreateShortcut($devShortcut).Description -ne 'cookdex-dev') { throw 'Dev shortcut changed production or selected the wrong target.' }
    # Exercise the owner's child-process suppression in Windows PowerShell 5.1:
    # benign native stderr must succeed, and a failing child must stop without
    # exposing its diagnostics. This never invokes either owner entry point.
    $fixture = Join-Path $testRoot 'synthetic-script.ps1'
    '$ErrorActionPreference = "Stop"; & cmd.exe /c "echo synthetic-private-stderr 1>&2"; exit 0' | Set-Content -LiteralPath $fixture -Encoding ascii
    Invoke-CookdexPrivateScript $fixture
    'throw "synthetic-private-failure"' | Set-Content -LiteralPath $fixture -Encoding ascii
    $refused = $false
    try { Invoke-CookdexPrivateScript $fixture } catch {
        $refused = $true
        if ($_.Exception.Message -match 'synthetic-private') { throw 'Child diagnostics escaped.' }
    }
    if (-not $refused) { throw 'Failed child script was accepted.' }
    $directory = Join-Path $testRoot 'signing'
    $keytool = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
    $password = New-CookdexSigningMaterial -Directory $directory -Keytool $keytool
    if ([Convert]::FromBase64String($password).Length -ne 32) { throw 'Password entropy check failed.' }
    if ($env:COOKDEX_KEYTOOL_PASSWORD -ne $previousPassword) { throw 'Password environment was not restored.' }
    $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $directory 'release-certificate.cer'))
    try {
        if (($cert.NotAfter - $cert.NotBefore).TotalDays -lt 10958 -or $cert.PublicKey.Key.KeySize -lt 4096) { throw 'Certificate strength/validity check failed.' }
    } finally { $cert.Dispose() }
    $fingerprint = Get-CookdexPublicFingerprint (Join-Path $directory 'release-certificate.cer')
    if ($fingerprint -notmatch '^[0-9a-f]{64}$') { throw 'Public fingerprint check failed.' }
    $acl = Get-Acl -LiteralPath $directory
    if (-not $acl.AreAccessRulesProtected) { throw 'Private folder ACL is inheriting access.' }
    $refused = $false
    try { $null = New-CookdexSigningMaterial -Directory $directory -Keytool $keytool } catch { $refused = $true }
    if (-not $refused) { throw 'Existing signing material was overwritten.' }
    if ((Get-CookdexPublicFingerprint (Join-Path $directory 'release-certificate.cer')) -ne $fingerprint) { throw 'Existing certificate changed.' }
    $env:COOKDEX_KEYTOOL_PASSWORD = $password
    Invoke-CookdexPrivateKeytool $keytool @('-list', '-keystore', (Join-Path $directory 'cookdex-release.p12'), '-storepass:env', 'COOKDEX_KEYTOOL_PASSWORD')
    # Prove the private key can sign, using an empty synthetic JAR, not an app.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $jar = Join-Path $testRoot 'synthetic.jar'
    $archive = [IO.Compression.ZipFile]::Open($jar, [IO.Compression.ZipArchiveMode]::Create)
    $entry = $archive.CreateEntry('synthetic.txt')
    $writer = [IO.StreamWriter]::new($entry.Open())
    $writer.Write('Synthetic signing fixture; no application data.')
    $writer.Dispose()
    $archive.Dispose()
    Invoke-CookdexPrivateKeytool (Join-Path $env:JAVA_HOME 'bin/jarsigner.exe') @('-keystore', (Join-Path $directory 'cookdex-release.p12'), '-storepass:env', 'COOKDEX_KEYTOOL_PASSWORD', $jar, 'cookdex-release')
    Invoke-CookdexPrivateKeytool (Join-Path $env:JAVA_HOME 'bin/jarsigner.exe') @('-verify', $jar)
    $env:COOKDEX_KEYTOOL_PASSWORD = 'deliberately-invalid-synthetic-password'
    $refused = $false
    try { Invoke-CookdexPrivateKeytool $keytool @('-list', '-keystore', (Join-Path $directory 'cookdex-release.p12'), '-storepass:env', 'COOKDEX_KEYTOOL_PASSWORD') }
    catch {
        $refused = $true
        if ($_.Exception.Message -match 'deliberately-invalid|storePassword|keyPassword' -or $_.Exception.Message.Contains($password)) { throw 'Private diagnostics escaped.' }
    }
    if (-not $refused) { throw 'Invalid password was accepted.' }
    $missing = Join-Path $testRoot 'missing.cer'
    $refused = $false
    try { $null = Get-CookdexPublicFingerprint $missing } catch { $refused = $true }
    if (-not $refused) { throw 'Missing certificate was accepted.' }
    Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
        $tokens = $null; $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'PowerShell parsing failed.' }
    }
    Write-Output 'PASS release tooling: isolated dev/production shortcuts, child stderr/exit handling, random password, RSA-4096/40-year certificate, private ACL, sign/verify, overwrite refusal, secret-safe failure and script parsing.'
} finally {
    $password = $null
    $env:COOKDEX_KEYTOOL_PASSWORD = $previousPassword
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^cookdex-signing-test-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
