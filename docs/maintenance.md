# Personal maintenance dashboard

`Invoke-NaraMaintenance.ps1` provides one read-only command for routine workstation checks.

## Default audit

```powershell
pwsh ./scripts/Invoke-NaraMaintenance.ps1 -OpenReport
```

The default run:

- verifies chezmoi state;
- checks the three local Git working trees;
- reads the latest GitHub Actions run for each local repository's committed HEAD;
- runs the NaraWorkstation and NaraSnippets validators;
- checks WinGet for available application updates;
- verifies the Ubuntu WSL registration;
- checks the age and size of the latest OneDrive WSL backup;
- writes local JSON and HTML reports under `Documents\NaraMaintenance`.

It does not install updates, modify repositories, or create a new backup.

## Commit-specific CI results

The CI row resolves the checkout's full HEAD SHA and filters `gh run list` by that commit. A run for another SHA is rejected. The row includes the local SHA and execution status/conclusion.

- `OK`: the selected run completed successfully for that SHA.
- `FAIL`: the selected run completed with failure, timeout, required action or startup failure.
- `WARN`: the run is pending/running, cancelled/skipped/neutral, absent, or cannot be queried or validated.

A missing run can mean the commit has not been pushed or no workflow ran for it; it is not a passing result. The audit does not fetch, push, rerun workflows or authenticate on your behalf.

This remains a view of the latest run for the local commit, not an aggregate of every workflow, required PR check or approval. Uncommitted changes are reported separately and are not covered by that commit's CI result.

Offline regression checks, with fictional Git/GitHub responses and no workstation actions:

```powershell
pwsh ./scripts/Test-NaraMaintenanceCi.ps1
```

## Explicit maintenance actions

Install available WinGet updates after a confirmation prompt:

```powershell
pwsh ./scripts/Invoke-NaraMaintenance.ps1 -UpdateApplications -OpenReport
```

Create a timestamped WSL export in OneDrive after a confirmation prompt:

```powershell
pwsh ./scripts/Invoke-NaraMaintenance.ps1 -BackupWSL -OpenReport
```

Both operations use PowerShell's high-impact confirmation model. Review the proposed target before accepting.

## Privacy

Reports contain health states, local paths, package-update availability, backup metadata and CI run IDs. They do not contain tokens or the contents of managed files. Keep reports local unless reviewed.
