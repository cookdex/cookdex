# Shared owner-script logic. Never emit private tool output or secret values.
function Get-CookdexReleaseSigningDirectory {
    $repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Join-Path (Split-Path $repository -Parent) 'cookdex-secrets/android-release'
}

function Invoke-CookdexPrivateKeytool {
    param([string]$Keytool, [string[]]$Arguments)
    # keytool can write informational output to stderr even on success in PS 5.1.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Keytool @Arguments *> $null
        $code = $LASTEXITCODE
    } catch { throw 'Signing tool failed. Private diagnostics were suppressed.' }
    finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) { throw 'Signing tool failed. Private diagnostics were suppressed.' }
}

function Invoke-CookdexPrivateScript {
    param([Parameter(Mandatory)][string]$Script, [string[]]$Arguments)
    # Keep native compiler stderr in the child console stream. Redirecting a
    # script directly with Stop preference turns benign stderr into terminating
    # NativeCommandError records in Windows PowerShell 5.1. The parent suppresses
    # all child output, and checks the child's actual exit code instead.
    $shell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    Invoke-CookdexPrivateKeytool $shell (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments)
}

function Get-CookdexPublicFingerprint {
    param([string]$Certificate)
    try {
        $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($Certificate)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            if ($cert.Subject -ne 'CN=Sylph, O=Sylph' -or $cert.Issuer -ne $cert.Subject -or
                $cert.NotAfter -lt (Get-Date) -or $cert.NotBefore -gt (Get-Date)) {
                throw 'Unexpected certificate.'
            }
            ([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose(); $cert.Dispose() }
    } catch { throw 'Release public certificate is missing or invalid. Restore the original signing backup.' }
}

function New-CookdexSigningMaterial {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Keytool)
    # The owner entry point supplies the fixed external directory; tests supply a
    # new temporary directory. Never reuse or overwrite even a partial setup.
    if (Test-Path -LiteralPath $Directory) { throw 'Signing folder already exists. Nothing was overwritten.' }
    if (-not (Test-Path -LiteralPath $Keytool -PathType Leaf)) { throw 'Build JDK keytool is missing.' }
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $password = $null
    $previousPassword = $env:COOKDEX_KEYTOOL_PASSWORD
    $stage = 'creating the private folder'
    try {
        New-Item -ItemType Directory -Path $Directory -ErrorAction Stop | Out-Null
        $stage = 'restricting folder permissions'
        $acl = Get-Acl -LiteralPath $Directory
        $acl.SetAccessRuleProtection($true, $false)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Directory -AclObject $acl
        $random.GetBytes($bytes)
        $password = [Convert]::ToBase64String($bytes)
        $env:COOKDEX_KEYTOOL_PASSWORD = $password
        $stage = 'generating the key'
        $key = Join-Path $Directory 'cookdex-release.p12'
        Invoke-CookdexPrivateKeytool $Keytool @('-genkeypair', '-noprompt', '-alias', 'cookdex-release',
            '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA', '-validity', '14610',
            '-dname', 'CN=Sylph,O=Sylph', '-storetype', 'PKCS12', '-keystore', $key,
            '-storepass:env', 'COOKDEX_KEYTOOL_PASSWORD', '-keypass:env', 'COOKDEX_KEYTOOL_PASSWORD')
        $stage = 'saving private build settings'
        $properties = "storeFile=cookdex-release.p12`nstorePassword=$password`nkeyAlias=cookdex-release`nkeyPassword=$password`n"
        [IO.File]::WriteAllText((Join-Path $Directory 'key.properties'), $properties, [Text.Encoding]::ASCII)
        $public = Join-Path $Directory 'release-certificate.cer'
        $stage = 'exporting the public certificate'
        Invoke-CookdexPrivateKeytool $Keytool @('-exportcert', '-alias', 'cookdex-release', '-keystore', $key,
            '-storetype', 'PKCS12', '-storepass:env', 'COOKDEX_KEYTOOL_PASSWORD', '-file', $public)
        $stage = 'checking the public certificate'
        $fingerprint = Get-CookdexPublicFingerprint $public
        [IO.File]::WriteAllText((Join-Path $Directory 'certificate-sha256.txt'), "$fingerprint`n", [Text.Encoding]::ASCII)
        # Only the owner entry point displays this, directly to their console.
        return $password
    } catch {
        throw "Key setup failed while $stage. No existing files were overwritten. Keep any partial signing folder and follow RELEASING.md. Private diagnostics were suppressed."
    } finally {
        $random.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
        $password = $null
        $properties = $null
        $env:COOKDEX_KEYTOOL_PASSWORD = $previousPassword
    }
}
