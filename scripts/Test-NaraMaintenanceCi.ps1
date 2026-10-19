#requires -Version 7.2
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load only the two functions under test, never the workstation audit/actions.
$source = Join-Path $PSScriptRoot 'Invoke-NaraMaintenance.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count) { throw 'Maintenance source has parser errors.' }
foreach ($name in @('Add-Check', 'Get-RepoHealth')) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($definitions.Count -ne 1) { throw "Expected one function named $name." }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$script:LocalHead = '1111111111111111111111111111111111111111'
$script:OtherHead = '2222222222222222222222222222222222222222'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('nara-ci-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0

function git {
    $global:LASTEXITCODE = 0
    $command = @($args | Select-Object -Skip 2) -join ' '
    switch ($command) {
        'rev-parse --is-inside-work-tree' { return 'true' }
        'branch --show-current' { return 'fixture' }
        'status --porcelain=v1 --untracked-files=all' { return }
        'rev-parse --abbrev-ref @{upstream}' { return 'origin/fixture' }
        'rev-list --left-right --count origin/fixture...HEAD' { return '0 0' }
        'rev-parse --verify HEAD' {
            if ($script:Scenario.Kind -eq 'HeadFailure') { $global:LASTEXITCODE = 128; return }
            if ($script:Scenario.Kind -eq 'InvalidHead') { return 'not-a-commit' }
            return $script:LocalHead
        }
        default { throw "Unexpected Git command in offline test: $command" }
    }
}

function gh {
    $script:GhCalls++
    $script:GhArguments = @($args)
    if ($args[0] -ne 'run' -or $args[1] -ne 'list') { throw 'Unexpected GitHub write or command.' }
    $global:LASTEXITCODE = if ($script:Scenario.Kind -eq 'CliError') { 7 } else { 0 }
    if ($script:Scenario.Kind -eq 'Malformed') { return '{ invalid JSON' }
    if ($script:Scenario.Kind -eq 'NoRuns') { return '[]' }
    if ($script:Scenario.Kind -eq 'MissingFields') { return '[{"conclusion":"success","databaseId":42}]' }

    $commitIndex = [Array]::IndexOf($script:GhArguments, '--commit')
    if ($commitIndex -lt 0 -or $script:GhArguments[$commitIndex + 1] -ne $script:LocalHead) {
        # A newer successful run for another commit must not green this checkout.
        return '[{"conclusion":"success","databaseId":99,"headSha":"2222222222222222222222222222222222222222","status":"completed"}]'
    }
    $run = [ordered]@{
        conclusion = if ($script:Scenario.ContainsKey('Conclusion')) { $script:Scenario.Conclusion } else { 'success' }
        databaseId = 42
        headSha = if ($script:Scenario.Kind -eq 'Mismatch') { $script:OtherHead } else { $script:LocalHead }
        status = if ($script:Scenario.ContainsKey('State')) { $script:Scenario.State } else { 'completed' }
    }
    ConvertTo-Json -InputObject @($run) -Compress
}

$scenarios = @(
    @{ Name='failed local commit despite newer unrelated success'; Kind='Run'; State='completed'; Conclusion='failure'; Expected='FAIL'; Detail='failure' }
    @{ Name='completed success for the local commit'; Kind='Run'; State='completed'; Conclusion='success'; Expected='OK'; Detail='success' }
    @{ Name='running local execution'; Kind='Run'; State='in_progress'; Conclusion=''; Expected='WARN'; Detail='in_progress' }
    @{ Name='queued local execution'; Kind='Run'; State='queued'; Conclusion=''; Expected='WARN'; Detail='queued' }
    @{ Name='no execution for the local commit'; Kind='NoRuns'; Expected='WARN'; Detail='No CI run' }
    @{ Name='timed-out local execution'; Kind='Run'; State='completed'; Conclusion='timed_out'; Expected='FAIL'; Detail='timed_out' }
    @{ Name='cancelled execution is not approval'; Kind='Run'; State='completed'; Conclusion='cancelled'; Expected='WARN'; Detail='cancelled' }
    @{ Name='CLI error with valid-looking stdout'; Kind='CliError'; Expected='WARN'; Detail='exit code 7' }
    @{ Name='mismatched SHA in filtered response'; Kind='Mismatch'; Expected='WARN'; Detail='does not match' }
    @{ Name='malformed JSON response'; Kind='Malformed'; Expected='WARN'; Detail='JSON' }
    @{ Name='missing run fields'; Kind='MissingFields'; Expected='WARN'; Detail='invalid run' }
    @{ Name='unresolvable local HEAD'; Kind='HeadFailure'; Expected='WARN'; Detail='local commit' }
    @{ Name='invalid local SHA'; Kind='InvalidHead'; Expected='WARN'; Detail='local commit' }
    @{ Name='unavailable GitHub authentication'; Kind='NoAuth'; Expected=''; Detail='' }
)

try {
    foreach ($scenario in $scenarios) {
        $script:Scenario = $scenario
        $script:checks = [System.Collections.Generic.List[object]]::new()
        $script:GhCalls = 0
        $script:GhArguments = @()
        try {
            Get-RepoHealth -Name 'Fixture' -Path $fixtureRoot -GitHubRepository 'example/fixture' -GitHubAvailable ($scenario.Kind -ne 'NoAuth')
            $ci = @($checks | Where-Object Area -eq 'GitHub CI')
            if ($scenario.Kind -eq 'NoAuth') {
                if ($ci.Count -ne 0 -or $script:GhCalls -ne 0) { throw 'Unavailable GitHub must not be queried or reported as success.' }
            } else {
                if ($ci.Count -ne 1) { throw "Expected one CI row, got $($ci.Count)." }
                if ($ci[0].Status -ne $scenario.Expected) { throw "Expected $($scenario.Expected), got $($ci[0].Status)." }
                if ($ci[0].Detail -notmatch [regex]::Escape($scenario.Detail)) { throw "Missing result detail: $($scenario.Detail)." }
                if ($scenario.Kind -in @('HeadFailure', 'InvalidHead')) {
                    if ($script:GhCalls -ne 0) { throw 'Invalid HEAD must stop before GitHub is queried.' }
                } else {
                    if ($script:GhCalls -ne 1) { throw "Expected one GitHub read, got $script:GhCalls." }
                    if ($ci[0].Detail -notmatch $script:LocalHead) { throw 'CI result must identify the local commit.' }
                }
            }
            $passed++
        } catch {
            $message = "$($scenario.Name): $($_.Exception.Message)"
            $failures.Add($message)
            Write-Host "FAIL: $message"
        }
    }
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
[pscustomobject]@{ Passed=$passed; Failed=$failures.Count; Total=$scenarios.Count; Offline=$true }
if ($failures.Count) { throw "$($failures.Count) maintenance CI test(s) failed." }
