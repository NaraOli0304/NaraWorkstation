[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Source,

    [Parameter(Mandatory)]
    [string]$Chezmoi,

    [string]$Destination = $HOME,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedManagedFiles = @(
    '.gitconfig',
    'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json',
    'AppData/Roaming/Code/User/settings.json',
    'AppData/Roaming/espanso/config/default.yml'
)

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source directory not found: $Source"
}

if (-not (Test-Path -LiteralPath $Chezmoi -PathType Leaf)) {
    throw "chezmoi executable not found: $Chezmoi"
}

$dryRunOutput = @(
    & $Chezmoi --source $Source --destination $Destination apply --dry-run 2>&1
)

if ($LASTEXITCODE -ne 0) {
    throw "Restore dry run failed with exit code $LASTEXITCODE."
}

$applyOutput = @(
    & $Chezmoi --source $Source --destination $Destination apply 2>&1
)

if ($LASTEXITCODE -ne 0) {
    throw "Restore failed with exit code $LASTEXITCODE."
}

$status = @(
    & $Chezmoi --source $Source --destination $Destination status 2>&1
)

if ($LASTEXITCODE -ne 0) {
    throw "Post-restore status failed with exit code $LASTEXITCODE."
}

if ($status.Count -gt 0) {
    throw 'Destination still differs from the managed source after restore.'
}

$managed = @(
    & $Chezmoi --source $Source --destination $Destination managed --include files
)

$unexpected = @($managed | Where-Object { $_ -notin $expectedManagedFiles })
$missing = @($expectedManagedFiles | Where-Object { $_ -notin $managed })

if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
    throw "Managed set mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
}

$result = [pscustomobject]@{
    Result = 'SUCCESS'
    ValidatedAtUtc = [DateTime]::UtcNow.ToString('o')
    ManagedFileCount = $managed.Count
    State = 'No differences'
    ManagedFiles = $managed
}

if ($OutputDirectory) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $result |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $OutputDirectory 'restore-result.json') -Encoding UTF8
}

$result
