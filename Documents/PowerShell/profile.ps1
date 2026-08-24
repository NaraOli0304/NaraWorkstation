function Invoke-NaraMaintenance {
    [CmdletBinding()]
    param(
        [switch]$UpdateApplications,
        [switch]$BackupWSL
    )

    $chezmoiExecutable = (Get-Command chezmoi -ErrorAction Stop).Source
    $sourcePath = & $chezmoiExecutable source-path

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourcePath)) {
        throw 'Unable to resolve the chezmoi source path.'
    }

    $maintenanceScript = Join-Path $sourcePath 'scripts\Invoke-NaraMaintenance.ps1'

    if (-not (Test-Path -LiteralPath $maintenanceScript -PathType Leaf)) {
        throw "Maintenance script not found: $maintenanceScript"
    }

    $parameters = @{
        OpenReport = $true
    }

    if ($UpdateApplications) {
        $parameters.UpdateApplications = $true
    }

    if ($BackupWSL) {
        $parameters.BackupWSL = $true
    }

    & $maintenanceScript @parameters
}

Set-Alias -Name nara-maintenance -Value Invoke-NaraMaintenance -Scope Global
