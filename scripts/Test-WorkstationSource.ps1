[CmdletBinding()]
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$managedFiles = @(
    'dot_gitconfig',
    'AppData/Roaming/Code/User/settings.json',
    'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json',
    'AppData/Roaming/espanso/config/default.yml'
)

foreach ($relativePath in $managedFiles) {
    $path = Join-Path $Root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required managed file is missing: $relativePath"
    }
}

$jsonFiles = @(
    'AppData/Roaming/Code/User/settings.json',
    'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
)

foreach ($relativePath in $jsonFiles) {
    $path = Join-Path $Root $relativePath
    Get-Content -LiteralPath $path -Raw |
        ConvertFrom-Json -Depth 100 |
        Out-Null
}

$scanFiles = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/]\.git[\\/]' -and
            $_.Extension -notin @('.md', '.ps1')
        }
)

$checks = [ordered]@{
    'private key' = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'GitHub token' = '(?i)\bgh[pousr]_[A-Za-z0-9_]{30,}\b'
    'JWT-like token' = '\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b'
    'credential assignment' = '(?i)\b(client_secret|access_token|refresh_token|password|api[_-]?key)\b\s*[:=]\s*\S{8,}'
    'corporate identifier' = '(?i)\b(atento|coem)\.(com|br|net|local)\b'
    'machine-specific home path' = '(?i)\b[A-Z]:\\Users\\[^\\\s]+'
}

foreach ($file in $scanFiles) {
    $fileContent = Get-Content -LiteralPath $file.FullName -Raw

    foreach ($check in $checks.GetEnumerator()) {
        if ($fileContent -match $check.Value) {
            throw "Privacy check failed ($($check.Key)): $($file.FullName)"
        }
    }

    $emailPattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    $emailMatches = [regex]::Matches($fileContent, $emailPattern)

    foreach ($emailMatch in $emailMatches) {
        $emailAddress = [string]$emailMatch.Value
        $isPublicNoReply = $emailAddress.EndsWith(
            '@users.noreply.github.com',
            [System.StringComparison]::OrdinalIgnoreCase
        )

        if (-not $isPublicNoReply) {
            throw "Non-public email found in $($file.FullName)."
        }
    }
}

$espansoPath = Join-Path $Root 'AppData/Roaming/espanso/config/default.yml'
$espansoConfig = Get-Content -LiteralPath $espansoPath -Raw
$shortcutPattern = '(?m)^search_shortcut:\s+ALT\+SHIFT\+SPACE\s*$'

if ($espansoConfig -notmatch $shortcutPattern) {
    throw 'Espanso search shortcut must remain ALT+SHIFT+SPACE to avoid the PowerToys conflict.'
}

[pscustomobject]@{
    Valid = $true
    ManagedFileCount = $managedFiles.Count
    ScannedFileCount = $scanFiles.Count
}
