# NaraWorkstation

[![validate](https://github.com/NaraOli0304/NaraWorkstation/actions/workflows/test.yml/badge.svg)](https://github.com/NaraOli0304/NaraWorkstation/actions/workflows/test.yml)
![Windows Sandbox restore verified](https://img.shields.io/badge/Windows%20Sandbox-restore%20verified-2ea44f)

Audited Windows 11 workstation configuration managed with [chezmoi](https://github.com/twpayne/chezmoi).

The repository captures a small, deliberate configuration surface instead of copying an entire user profile:

- Git identity and GitHub CLI credential helper configuration;
- Visual Studio Code user settings;
- Windows Terminal settings;
- Espanso application settings;
- a PowerShell 7 profile exposing the audited maintenance command.

Personal Espanso matches live separately in [NaraSnippets](https://github.com/NaraOli0304/NaraSnippets).

## Safety model

- Files are selected individually.
- No shell history, browser data, credentials or tokens are managed.
- CI scans for private keys, token formats, credential assignments, corporate identifiers and machine-specific home paths.
- CI rejects unexpected root files and unexpected files under the managed `AppData` tree.
- Documentation, tests and workflows are excluded from `chezmoi apply`.
- Non-Windows systems are excluded by `.chezmoiignore`.

## Tested recovery

The configuration was restored successfully into a disposable Windows Sandbox with networking disabled:

- dry run completed;
- the approved workstation files restored;
- final `chezmoi status` returned no differences;
- bootstrap process returned exit code 0.

See the [sanitized restore evidence](docs/restore-validation.md). Raw verbose logs are intentionally not published because they can reveal configuration values.

The reusable validator is available at `scripts/Test-SandboxRestore.ps1`. GitHub-hosted CI validates its PowerShell syntax, while the actual Sandbox restore remains an explicit isolated Windows test because hosted runners do not provide nested Windows Sandbox execution.

## Personal maintenance dashboard

After applying the chezmoi source, run a read-only health audit from any PowerShell 7 directory:

```powershell
nara-maintenance
```

Optional explicit operations remain available:

```powershell
nara-maintenance -UpdateApplications
nara-maintenance -BackupWSL
```

The repository script remains available directly as `scripts/Invoke-NaraMaintenance.ps1`.

It checks application updates, the three personal repositories, GitHub Actions, chezmoi state, local validators, WSL and the latest OneDrive WSL backup. Reports are written locally to `Documents\NaraMaintenance`.

Updates and WSL exports require explicit switches and a high-impact confirmation prompt. See the [maintenance guide](docs/maintenance.md).

## Install safely

Install chezmoi:

```powershell
winget install --id twpayne.chezmoi --source winget
```

Initialize without applying:

```powershell
chezmoi init NaraOli0304/NaraWorkstation
chezmoi diff
```

Only after reviewing the diff:

```powershell
chezmoi apply
```

## Update workflow

After changing a managed file:

```powershell
chezmoi re-add
chezmoi diff
chezmoi cd
git status --short
```

Review every diff before committing.

## License

MIT
