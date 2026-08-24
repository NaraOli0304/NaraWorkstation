# Windows Sandbox restore validation

The workstation source was restored into a disposable Windows Sandbox on 2026-08-24.

## Result

- Result: **SUCCESS**
- Managed files: **4**
- Final state: **No differences**
- Bootstrap exit code: **0**
- Network access during validation: **Disabled**
- Source mapping: **Read-only**
- Result mapping: **Write-enabled**

Validated targets:

- `.gitconfig`
- Windows Terminal settings
- Visual Studio Code user settings
- Espanso configuration

## What the test proved

1. The source can be consumed outside the original Windows profile.
2. A dry run completes before any files are applied.
3. The configuration restores successfully into a clean disposable profile.
4. A post-restore `chezmoi status` returns no differences.
5. The restored managed set contains exactly the four approved files.

The first validation run exposed an unexpected empty root file named `--repo`. It was not committed to Git, but chezmoi correctly treated it as managed content. The source validator now rejects unexpected root files and unexpected files under `AppData`.

## Privacy

Raw transcripts are intentionally not committed because a verbose restore can reveal configuration values. This document records only the sanitized outcome.

## Reproduce

From inside an isolated Windows environment:

```powershell
pwsh ./scripts/Test-SandboxRestore.ps1 `
    -Source <CHEZMOI_SOURCE> `
    -Chezmoi <PATH_TO_CHEZMOI_EXE> `
    -Destination $HOME `
    -OutputDirectory <SAFE_OUTPUT_DIRECTORY>
```

Review the generated `restore-result.json`. Do not publish verbose restore logs without inspecting and redacting them.
