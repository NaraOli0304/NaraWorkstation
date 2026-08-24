#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$UpdateApplications,
    [switch]$BackupWSL,
    [switch]$OpenReport,
    [string]$WslDistribution = 'Ubuntu-24.04',
    [string]$ReportDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'NaraMaintenance')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Area, [string]$Check, [ValidateSet('OK','WARN','FAIL','INFO')][string]$Status, [string]$Detail)
    $checks.Add([pscustomobject]@{ Area=$Area; Check=$Check; Status=$Status; Detail=$Detail })
}

function Get-RepoHealth {
    param([string]$Name, [string]$Path, [string]$GitHubRepository, [bool]$GitHubAvailable)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Add-Check 'Repositories' $Name 'FAIL' "Local path not found: $Path"
        return
    }

    $isRepo = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $isRepo -ne 'true') {
        Add-Check 'Repositories' $Name 'FAIL' 'Directory is not a Git working tree.'
        return
    }

    $branch = & git -C $Path branch --show-current 2>$null
    $changes = @(& git -C $Path status --porcelain=v1 --untracked-files=all 2>$null)
    if ($changes.Count -eq 0) {
        Add-Check 'Repositories' "$Name working tree" 'OK' "Clean on branch $branch."
    } else {
        Add-Check 'Repositories' "$Name working tree" 'WARN' "$($changes.Count) local change(s) on branch $branch."
    }

    $upstream = & git -C $Path rev-parse --abbrev-ref '@{upstream}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) {
        $counts = (& git -C $Path rev-list --left-right --count "$upstream...HEAD" 2>$null) -split '\s+'
        $behind = [int]$counts[0]
        $ahead = [int]$counts[1]
        $state = if ($behind -eq 0 -and $ahead -eq 0) { 'OK' } else { 'WARN' }
        Add-Check 'Repositories' "$Name synchronization" $state "Ahead: $ahead; behind: $behind (local refs)."
    } else {
        Add-Check 'Repositories' "$Name synchronization" 'WARN' 'No upstream branch configured.'
    }

    if ($GitHubAvailable) {
        try {
            $json = & gh run list --repo $GitHubRepository --limit 1 --json conclusion,databaseId 2>$null
            $run = @($json | ConvertFrom-Json)[0]
            $state = if ($run.conclusion -eq 'success') { 'OK' } else { 'WARN' }
            Add-Check 'GitHub CI' $Name $state "Latest run: $($run.conclusion); ID $($run.databaseId)."
        } catch {
            Add-Check 'GitHub CI' $Name 'WARN' $_.Exception.Message
        }
    }
}

if ($UpdateApplications -and $PSCmdlet.ShouldProcess('supported WinGet packages', 'Install available updates')) {
    & winget upgrade --all --source winget --accept-source-agreements --accept-package-agreements
    $state = if ($LASTEXITCODE -eq 0) { 'OK' } else { 'WARN' }
    Add-Check 'Applications' 'WinGet update operation' $state "Exit code: $LASTEXITCODE."
}

$oneDrive = [Environment]::GetEnvironmentVariable('OneDrive','User')
if (-not $oneDrive) { $oneDrive = $env:OneDrive }
$backupDirectory = if ($oneDrive) { Join-Path $oneDrive 'Backups\WSL' } else { $null }

if ($BackupWSL) {
    if (-not $backupDirectory) { throw 'OneDrive path was not found.' }
    if ($PSCmdlet.ShouldProcess($WslDistribution, "Terminate and export to $backupDirectory")) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backupPath = Join-Path $backupDirectory ("{0}-{1}.tar" -f $WslDistribution,(Get-Date -Format 'yyyyMMdd-HHmmss'))
        & wsl --terminate $WslDistribution
        & wsl --export $WslDistribution $backupPath
        $state = if ($LASTEXITCODE -eq 0) { 'OK' } else { 'FAIL' }
        Add-Check 'Backups' 'WSL export' $state "Exit code: $LASTEXITCODE."
    }
}

$githubAvailable = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    & gh auth status *> $null
    if ($LASTEXITCODE -eq 0) {
        $githubAvailable = $true
        Add-Check 'GitHub' 'Authentication' 'OK' 'GitHub CLI authentication is active.'
    } else { Add-Check 'GitHub' 'Authentication' 'WARN' 'GitHub CLI is not authenticated.' }
} else { Add-Check 'GitHub' 'Authentication' 'WARN' 'GitHub CLI is unavailable.' }

if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    $chezmoiStatus = @(& chezmoi status 2>&1)
    if ($LASTEXITCODE -eq 0 -and $chezmoiStatus.Count -eq 0) {
        Add-Check 'Configuration' 'chezmoi status' 'OK' 'Destination matches the source.'
    } elseif ($LASTEXITCODE -eq 0) {
        Add-Check 'Configuration' 'chezmoi status' 'WARN' "$($chezmoiStatus.Count) difference(s) detected."
    } else { Add-Check 'Configuration' 'chezmoi status' 'FAIL' "Exit code: $LASTEXITCODE." }
    $workstationPath = & chezmoi source-path
} else {
    Add-Check 'Configuration' 'chezmoi status' 'FAIL' 'chezmoi is unavailable.'
    $workstationPath = Join-Path $HOME '.local\share\chezmoi'
}

$repos = @(
    @{Name='NaraWorkstation';Path=$workstationPath;GitHub='NaraOli0304/NaraWorkstation'},
    @{Name='NaraSnippets';Path=(Join-Path $HOME 'Projects\NaraSnippets');GitHub='NaraOli0304/NaraSnippets'},
    @{Name='ChangePack365';Path=(Join-Path $HOME 'Projects\ChangePack365');GitHub='NaraOli0304/ChangePack365'}
)
foreach ($repo in $repos) { Get-RepoHealth $repo.Name $repo.Path $repo.GitHub $githubAvailable }

$workstationValidator = Join-Path $workstationPath 'scripts\Test-WorkstationSource.ps1'
if (Test-Path -LiteralPath $workstationValidator) {
    try {
        $v = & $workstationValidator -Root $workstationPath
        Add-Check 'Validation' 'NaraWorkstation' 'OK' "$($v.ManagedFileCount) managed; $($v.PowerShellFileCount) scripts parsed."
    } catch { Add-Check 'Validation' 'NaraWorkstation' 'FAIL' $_.Exception.Message }
}

$snippetsValidator = Join-Path $HOME 'Projects\NaraSnippets\scripts\Test-NaraSnippets.ps1'
if (Test-Path -LiteralPath $snippetsValidator) {
    try {
        $v = & $snippetsValidator
        Add-Check 'Validation' 'NaraSnippets' 'OK' "$($v.TriggerCount) trigger(s) validated."
    } catch { Add-Check 'Validation' 'NaraSnippets' 'FAIL' $_.Exception.Message }
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    $upgradeOutput = @(& winget upgrade --source winget --accept-source-agreements 2>&1)
    $upgradeText = $upgradeOutput -join [Environment]::NewLine
    $none = '(?i)(No available upgrade|No newer package versions|Nenhuma atualiza|Não há atualiza)'
    if ($LASTEXITCODE -ne 0) { Add-Check 'Applications' 'Available updates' 'WARN' "Exit code: $LASTEXITCODE." }
    elseif ($upgradeText -match $none) { Add-Check 'Applications' 'Available updates' 'OK' 'No updates reported by WinGet.' }
    else { Add-Check 'Applications' 'Available updates' 'WARN' 'WinGet reports available updates.' }
} else { Add-Check 'Applications' 'Available updates' 'FAIL' 'WinGet is unavailable.' }

$wslList = @(& wsl --list --quiet 2>$null) | Where-Object { $_ }
if (@($wslList | Where-Object { $_.Trim() -eq $WslDistribution }).Count -gt 0) {
    Add-Check 'WSL' $WslDistribution 'OK' 'Distribution is registered.'
} else { Add-Check 'WSL' $WslDistribution 'WARN' 'Distribution was not returned.' }

if ($backupDirectory -and (Test-Path -LiteralPath $backupDirectory)) {
    $latest = Get-ChildItem $backupDirectory -File -Filter "$WslDistribution*.tar" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $age = [math]::Floor(((Get-Date)-$latest.LastWriteTime).TotalDays)
        $state = if ($age -le 14) { 'OK' } else { 'WARN' }
        Add-Check 'Backups' 'Latest WSL backup' $state "$($latest.Name); $([math]::Round($latest.Length/1GB,2)) GB; $age day(s) old."
    } else { Add-Check 'Backups' 'Latest WSL backup' 'WARN' 'No backup was found.' }
} else { Add-Check 'Backups' 'Latest WSL backup' 'WARN' 'Backup directory was not found.' }

$summary = [pscustomobject]@{
    GeneratedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz');Computer=$env:COMPUTERNAME
    Ok=@($checks|Where-Object Status -eq 'OK').Count;Warn=@($checks|Where-Object Status -eq 'WARN').Count
    Fail=@($checks|Where-Object Status -eq 'FAIL').Count;Checks=$checks
}

New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $ReportDirectory "maintenance-$stamp.json"
$htmlPath = Join-Path $ReportDirectory "maintenance-$stamp.html"
$summary | ConvertTo-Json -Depth 8 | Set-Content $jsonPath -Encoding UTF8

function H([object]$Value) { [System.Net.WebUtility]::HtmlEncode([string]$Value) }
$rows = foreach ($c in $checks) { "<tr><td>$(H $c.Area)</td><td>$(H $c.Check)</td><td class='$($c.Status.ToLower())'>$(H $c.Status)</td><td>$(H $c.Detail)</td></tr>" }
$html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Nara Maintenance</title>
<style>body{font-family:Segoe UI;background:#071426;color:#eaf2ff;margin:0;padding:32px}main{max-width:1180px;margin:auto}.tag{color:#45d7ff;font-weight:700;letter-spacing:.16em}h1{font-size:42px}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin:28px 0}.card,section{background:#0d2037;border:1px solid #294663;border-radius:18px;padding:22px}.card b{display:block;font-size:42px}.ok{color:#52e58b}.warn{color:#ffc83d}.fail{color:#ff6b81}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:13px;border-bottom:1px solid #294663}th{color:#9eb2cc}@media(max-width:720px){.cards{grid-template-columns:1fr}}</style></head>
<body><main><div class="tag">NARA WORKSTATION</div><h1>Painel de manutenção</h1><p>$(H $summary.GeneratedAt) · $(H $summary.Computer)</p><div class="cards"><div class="card">Aprovados<b class="ok">$($summary.Ok)</b></div><div class="card">Atenção<b class="warn">$($summary.Warn)</b></div><div class="card">Falhas<b class="fail">$($summary.Fail)</b></div></div><section><table><thead><tr><th>Área</th><th>Verificação</th><th>Estado</th><th>Detalhe</th></tr></thead><tbody>$($rows -join [Environment]::NewLine)</tbody></table></section><p>Relatório local sem tokens ou conteúdo dos arquivos gerenciados.</p></main></body></html>
"@
Set-Content $htmlPath $html -Encoding UTF8
Write-Host "OK: $($summary.Ok) | Atenção: $($summary.Warn) | Falhas: $($summary.Fail)"
Write-Host "HTML: $htmlPath"
Write-Host "JSON: $jsonPath"
if ($OpenReport) { Invoke-Item $htmlPath }
$summary
