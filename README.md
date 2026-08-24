# NaraWorkstation

Audited Windows 11 workstation configuration managed with [chezmoi](https://github.com/twpayne/chezmoi).

The repository captures a small, deliberate configuration surface instead of copying an entire user profile:

- Git identity and GitHub CLI credential helper configuration;
- Visual Studio Code user settings;
- Windows Terminal settings;
- Espanso application settings.

Personal Espanso matches live separately in [NaraSnippets](https://github.com/NaraOli0304/NaraSnippets).

## Safety model

- Files are selected individually.
- No shell history, browser data, credentials or tokens are managed.
- CI scans for private keys, token formats, credential assignments, corporate identifiers and machine-specific home paths.
- Documentation, tests and workflows are excluded from `chezmoi apply`.
- Non-Windows systems are excluded by `.chezmoiignore`.

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
