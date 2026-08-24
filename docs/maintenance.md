# Personal maintenance dashboard

`Invoke-NaraMaintenance.ps1` provides one read-only command for routine workstation checks.

## Default audit

```powershell
pwsh ./scripts/Invoke-NaraMaintenance.ps1 -OpenReport
```

The default run:

- verifies chezmoi state;
- checks the three local Git working trees;
- reads the latest GitHub Actions result for each repository;
- runs the NaraWorkstation and NaraSnippets validators;
- checks WinGet for available application updates;
- verifies the Ubuntu WSL registration;
- checks the age and size of the latest OneDrive WSL backup;
- writes local JSON and HTML reports under `Documents\NaraMaintenance`.

It does not install updates, modify repositories, or create a new backup.

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
